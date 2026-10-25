| .FUNC RgnOp,7
| .REF SectScan,DiffScan,UnionScan,XorScan,InsetScan,SetSize
| -------------------------------------------------------------------
|
| FUNCTION RgnOp(rgnA,rgnB: RgnHandle;
| bufHandle: Handle;
| maxBytes: INTEGER;
| op,dh: INTEGER;
| okGrow: BOOLEAN): INTEGER;
|
| Computes the intersection, difference, union, or XOR of two regions,
| or the horizontal inset of one region, and stores the result as an
| unpacked array of sorted inversion points in bufHandle. Returns the
| number of points as the function value. BufHandle will be grown only
| if more space is needed needed and okGrow is true.
|
| OP = 0: SectScan
| 2: DIFF A-B
| 4: UNION
| 6: XOR
| 8: HORIZ INSET
|
|
| A6 OFFSETS OF PARAMETERS AND LOCALS AFTER LINK:
|
| Called during boot (7,474 times in 30s trace).

| -------------------------------------------------------------------
|
| FUNCTION RgnOp(rgnA,rgnB: RgnHandle;
|                bufHandle: Handle;
|                maxBytes: INTEGER;
|                op,dh: INTEGER;
|                okGrow: BOOLEAN): INTEGER;
|
| Computes the intersection, difference, union, or XOR of two
| regions, or the horizontal inset of one region, and stores the
| result as an unpacked array of sorted inversion points in
| BufHandle. Returns the number of points as the function value.
| BufHandle will be grown only if more space is needed and OkGrow
| is true.
|
|   OP = 0: SectScan
|        2: DIFF A-B
|        4: UNION
|        6: XOR
|        8: HORIZ INSET
|
RGNOP:
    LINK	A6,#-0x56                              | allocate stack frame
    MOVEM.L	D3-D7/A2-A4,-(A7)                   | save regs
    MOVE.L	A7,-0x56(A6)                         | remember stack ptr
| ------------------------------------------------------------
|
| De-reference RgnA and RgnB and offset to first RgnData.
| If either is rectangular, replace it with an expanded one.
|
    LEA.L	-0x4E(A6),A2                          | point to fake area
    LEA.L	0x18(A6),A0                           | point to RgnA handle
    BSR.W	EXPAND                                | de-reference and expand
    MOVEA.L	A0,A3                               | save RgnA data ptr in A3
    LEA.L	0x14(A6),A0                           | point to RgnB handle
    BSR.W	EXPAND                                | de-reference and expand
    MOVEA.L	A0,A4                               | save RgnB data ptr in A4
| -----------------------------------------------------------
|
| Set up a case jump based on op
|
    LEA.L	SECTSCAN(PC),A0                       | get address of SectScan
    MOVE.W	0xC(A6),D0                           | get op parameter
    BEQ.B	CASEOK                                | br if op = SectScan
    LEA.L	DIFFSCAN(PC),A0                       | get address of DiffScan
    SUBQ.W	#0x2,D0                              | is op = DiffScan (2) ?
    BEQ.B	CASEOK                                | br if op = DIFF
    LEA.L	UNIONSCAN(PC),A0                      | get address of UnionScan
    SUBQ.W	#0x2,D0                              | is op = UnionScan (4) ?
    BEQ.B	CASEOK                                | br if op = UNION
    LEA.L	XORSCAN(PC),A0                        | get address of XorScan
    SUBQ.W	#0x2,D0                              | is op = XorScan (6) ?
    BEQ.B	CASEOK                                | br if op = XOR
    LEA.L	INSETSCAN(PC),A0                      | else op = INSET
CASEOK:
    MOVE.L	A0,-0x52(A6)                         | save for later
    MOVE.L	A7,D0                                | get current stack pointer
    SUB.L	(HeapEnd).W,D0                        | subtract HeapEnd to get stack avail
    SUBI.L	#0x400,D0                            | subtract 1K for safety margin
    CMPI.L	#0xC8,D0                             | is available stack < 200 bytes ?
| -----------------------------------------------------------------
|
| Calc BufSize based on StackAvail and allocate 5 scan buffers
|
    BGE.B	STKOK1                                | no, continue
    MOVE.W	#0x28,D0                             | yes, make BufSize = 40 bytes
    BRA.B	ALLOC                                 | and continue
| ----------------------------------------------------------
|
| STKOK1 -- divide stack avail by 5 (one buffer each)
|
STKOK1:
    DIVS.W	#0x5,D0                              | no, divide for 5 buffers
    BVC.B	STKOK2                                | overflow ?
    MOVE.W	#0x7530,D0                           | yes, use 30K bytes
STKOK2:
    BCLR	#0x0,D0                                | make BufSize even
ALLOC:
    SUBA.W	D0,A7                                | allocate one buffer
    MOVE.L	A7,-0x4(A6)                          | remember buffer pointer
    SUBA.W	D0,A7                                | allocate one buffer
    MOVE.L	A7,-0x8(A6)                          | remember buffer pointer
    SUBA.W	D0,A7                                | allocate one buffer
    MOVE.L	A7,-0xC(A6)                          | remember buffer pointer
    SUBA.W	D0,A7                                | allocate one buffer
    MOVE.L	A7,-0x10(A6)                         | remember buffer pointer
    SUBA.W	D0,A7                                | allocate one buffer
    MOVE.L	A7,-0x14(A6)                         | remember buffer pointer
| -----------------------------------------------------------
|
| Init assorted pointers
|
    MOVEA.L	0x10(A6),A0                         | get BufHandle
    MOVEA.L	(A0),A0                             | de-reference it
    MOVE.L	A0,-0x1E(A6)                         | BufPtr := BufStart
    ANDI.W	#0xFFF8,0xE(A6)                      | round MaxBytes down to mult of 8
    ADDA.W	0xE(A6),A0                           | add to BufStart to get BufLimit
    MOVE.L	A0,-0x22(A6)                         | BufLimit := BufStart + MaxBytes
    MOVEA.L	-0x4(A6),A0                         | get pointer to scan buffer 1 (ScanA)
    MOVE.L	A0,D4                                | ScanA := @SCAN1
    MOVE.W	#0x7FFF,D0                           | get end marker
    MOVE.W	D0,(A0)                              | init ScanA to empty
    MOVEA.L	-0x8(A6),A0                         | get pointer to scan buffer 2 (ScanB)
    MOVE.L	A0,D5                                | ScanB := @SCAN2
    MOVE.W	D0,(A0)                              | init ScanB to empty
    MOVEA.L	-0xC(A6),A0                         | get pointer to scan buffer 3 (ScanC)
    MOVE.L	A0,D6                                | ScanC := @SCAN3
    MOVE.W	D0,(A0)                              | init ScanC to empty
    MOVEA.L	-0x10(A6),A0                        | get pointer to scan buffer 4 (TempScan)
    MOVE.L	A0,D7                                | TempScan := @SCAN4
    MOVE.W	(A3)+,-0x16(A6)                      | NextA := first vert in A
    MOVE.W	(A4)+,-0x18(A6)                      | NextB := first vert in B
    CMPI.W	#0x8,0xC(A6)                         | is op = InsetScan (8) ?
    BNE.B	RGNOP_NXTVERT                         | no, continue
    MOVE.W	D0,-0x18(A6)                         | yes, NextB := 32767
RGNOP_NXTVERT:
    MOVE.W	-0x16(A6),D0                         | get next vert in A
    CMP.W	-0x18(A6),D0                          | which comes first ?
    BEQ.B	BOTH                                  | same, update both rgns
    BGT.B	UPDATEB                               | B, update RgnB only
    BSR.B	UPDATEA                               | A, update RgnA only
    BRA.B	CALC                                  | calc new C-scan
| ----------------------------------------------------------
|
| UPDATEA -- update RgnA scan: XorScan(PtrA, ScanA, TempScan)
|
UPDATEA:
    MOVE.W	-0x16(A6),-0x1A(A6)                  | vert := NextA
    MOVEA.L	A3,A0                               | SrcA := PtrA
    MOVEA.L	D4,A1                               | SrcB := ScanA
    MOVEA.L	D7,A2                               | DstC := TempScan
    JSR	XORSCAN(PC)                             | XorScan(PtrA,ScanA,TempScan)
    MOVEA.L	A0,A3                               | bump PtrA to end of scan
    MOVE.W	(A3)+,-0x16(A6)                      | NextA := next vert
    EXG	D4,D7                                   | swap ScanA and TempScan
    RTS                                         | return to local caller
| ----------------------------------------------------------
|
| BOTH -- both regions hit same vert: update both
|
BOTH:
    CMPI.W	#0x7FFF,D0                           | have we reached the end marker ?
    BEQ.W	RGNOP_DONE                            | yes, we're all finished
    BSR.B	UPDATEA                               | update RgnA
UPDATEB:
    MOVE.W	-0x18(A6),-0x1A(A6)                  | vert := NextB
    MOVEA.L	A4,A0                               | SrcA := PtrB
    MOVEA.L	D5,A1                               | SrcB := ScanB
    MOVEA.L	D7,A2                               | DstC := TempScan
    JSR	XORSCAN(PC)                             | XorScan(PtrB,ScanB,TempScan)
    MOVEA.L	A0,A4                               | bump PtrB to end of scan
    MOVE.W	(A4)+,-0x18(A6)                      | NextB := next vert
    EXG	D7,D5                                   | swap ScanB and TempScan
| ---------------------------------------------------------
|
| CALC -- calculate SectScan, DIFF, UNION, XOR, or INSET into ScanC
|
CALC:
    MOVEA.L	D4,A0                               | point to ScanA
    MOVEA.L	D5,A1                               | point to ScanB
    MOVEA.L	D7,A2                               | point to TempScan
    MOVE.W	0xA(A6),D2                           | pass dh parameter in D2
    PEA.L	CHANGES(PC)                           | push return addr
    MOVE.L	-0x52(A6),-(A7)                      | push case jump
    RTS                                         | do case JSR
| -------------------------------------------------------------
|
| CHANGES -- find any changes not in previous ScanC, then update ScanC
|
CHANGES:
    MOVEA.L	D7,A0                               | get TempScan
    MOVEA.L	D6,A1                               | get ScanC
    MOVEA.L	-0x14(A6),A2                        | get output scan
    JSR	XORSCAN(PC)                             | XorScan(TempScan,ScanC,@SCAN5)
    EXG	D7,D6                                   | swap TempScan and ScanC
    MOVEA.L	-0x14(A6),A0                        | point to output scan
    MOVEA.L	-0x1E(A6),A1                        | point to dst point buffer
    MOVEA.L	-0x22(A6),A2                        | get BufLimit
    MOVE.L	-0x1A(A6),D0                         | get vert coord in hi word
    BRA.B	OUTTEST                               | go to loop start
| ----------------------------------------------------------
|
| CHANGES_NO -- emit one (left,right) point pair into output buffer
|
CHANGES_NO:
    MOVE.W	(A0)+,D0                             | insert horiz coord into low word of D0
    MOVE.L	D0,(A1)+                             | put left point
    MOVE.W	(A0)+,D0                             | insert horiz coord into low word of D0
    MOVE.L	D0,(A1)+                             | put right point
OUTTEST:
    CMPA.L	A2,A1                                | is BufPtr >= BufLimit ?
    BCS.B	OUTTEST_NO                            | branch if buffer not full yet
| -----------------------------------------------------------
|
| The point buffer is full. Grow it if OkGrow is true,
| else abort and return PtCount = 0.
|
    TST.B	0x8(A6)                               | OkGrow ?
    BEQ.W	RGNOP_ABORT                           | no, abort
    MOVE.L	A0,D1                                | save scan pointer
    MOVEA.L	0x18(A6),A0                         | get RgnA handle
    SUBA.L	(A0),A3                              | A3 := PtrA offset
    MOVEA.L	0x14(A6),A0                         | get RgnB handle
    SUBA.L	(A0),A4                              | A4 := PtrB offset
    MOVEA.L	0x10(A6),A0                         | get BufHandle
    SUBA.L	(A0),A1                              | A1 := BufPtr offset
    SUBA.L	(A0),A2                              | A2 := BufLimit offset
    ADDA.W	#0x100,A2                            | grow buffer by 256 bytes
    MOVEM.L	D0-D2/A0-A2,-(A7)                   | save offsets across SetHSize
    MOVE.L	A0,-(A7)                             | push BufHandle
    MOVE.W	A2,-(A7)                             | push new size
    JSR	SETHSIZE(PC)                            | grow it
    MOVEM.L	(A7)+,D0-D2/A0-A2                   | restore offsets
    MOVEA.L	0x18(A6),A0                         | get RgnA handle
    ADDA.L	(A0),A3                              | restore PtrA
    MOVEA.L	0x14(A6),A0                         | get RgnB handle
    ADDA.L	(A0),A4                              | restore PtrB
    MOVEA.L	0x10(A6),A0                         | get BufHandle
    ADDA.L	(A0),A1                              | restore BufPtr
    ADDA.L	(A0),A2                              | restore BufLimit
    MOVE.L	A2,-0x22(A6)                         | save new BufLimit
    MOVEA.L	D1,A0                               | restore scan pointer
OUTTEST_NO:
    CMPI.W	#0x7FFF,(A0)                         | end marker ?
    BNE.B	CHANGES_NO                            | no, emit another point pair
    MOVE.L	A1,-0x1E(A6)                         | save BufPtr
    BRA.W	RGNOP_NXTVERT                         | back to next vert
| ----------------------------------------------------------
|
| EXPAND -- de-reference RgnHandle and offset to first RgnData.
| If region is rectangular (size = 10), expand it into a fake
| 18-byte rect-rgn data block at A2 with explicit (top,left,
| right,$7FFF) (bottom,left,right,$7FFF,$7FFF) inversion points.
|
EXPAND:
    MOVEA.L	(A0),A1                             | de-reference handle
    MOVEA.L	(A1),A1                             | de-reference master ptr
    CMPI.W	#0xA,(A1)                            | is region rectangular ?
    BNE.B	RGNOP_NOTRECT                         | no, continue
    MOVE.L	A2,(A0)                              | yes, redirect handle to fake area
    LEA.L	-0x6(A2),A0                           | point to fake master cell
    MOVE.L	A0,(A2)+                             | install fake master
    MOVE.L	0x2(A1),(A2)+                        | top, left
    MOVE.W	0x8(A1),(A2)+                        | right
    MOVE.W	#0x7FFF,D0                           | end marker
    MOVE.W	D0,(A2)+                             | end of top scanline
    MOVE.W	0x6(A1),(A2)+                        | bottom
    MOVE.W	0x4(A1),(A2)+                        | left (closing edge)
    MOVE.W	0x8(A1),(A2)+                        | right (closing edge)
    MOVE.W	D0,(A2)+                             | end of bottom scanline
    MOVE.W	D0,(A2)+                             | end of region marker
    MOVEA.L	A0,A1                               | use fake area as A1
RGNOP_NOTRECT:
    LEA.L	0xA(A1),A0                            | skip past RgnSize+RgnBBox
    RTS                                         | return from RGNOP_NOTRECT
| ----------------------------------------------------------
|
| RGNOP_ABORT
|
| Called during boot.
RGNOP_ABORT:
    MOVE.L	A1,-0x1E(A6)                         | snap BufPtr to its start (NPoints = 0)
RGNOP_DONE:
    MOVE.L	-0x1E(A6),D0                         | get BufPtr
    MOVEA.L	0x10(A6),A0                         | get BufHandle
    SUB.L	(A0),D0                               | bytes used = BufPtr - BufStart
    LSR.W	#0x2,D0                               | div by 4 for NPoints
    MOVE.W	D0,0x1C(A6)                          | return NPoints
    MOVEA.L	-0x56(A6),A7                        | strip scan buffers
    MOVEM.L	(A7)+,D3-D7/A2-A4                   | restore regs
    UNLK	A6                                     | unlink stack frame
    MOVEA.L	(A7)+,A0                            | get return address
    ADDA.W	#0x14,A7                             | pop 20 bytes of parameters
    JMP	(A0)                                    | tail-call return from RGNOP_DONE via A0
| ---------------------------------------------------------
|
| PROCEDURE SectScan(srcA, srcB, dstC: ScanPtr);
|
| Calculate the intersection, difference, or union of two
| inversion scans. Each input scan is a sorted array of
| integers terminated by 32767.
|
| INPUTS:  A0 SrcA, A1 SrcB, A2 DstC
|
| CLOBBERS D0-D3, A0-A2
|
SECTSCAN:
    CLR.W	D2                                    | reset AState off
    CLR.W	D3                                    | reset BState off
    BRA.B	SECTSCAN_SHARE                        | share code
| ----------------------------------------------------------
|
| DiffScan
|
DIFFSCAN:
    CLR.W	D2                                    | reset AState off
    BRA.B	UNION2                                | share code
| ----------------------------------------------------------
|
| UnionScan
|
UNIONSCAN:
    MOVEQ.L	#-0x1,D2                            | set AState on
UNION2:
    MOVEQ.L	#-0x1,D3                            | set BState on
SECTSCAN_SHARE:
    MOVE.W	(A0)+,D0                             | get NextA
    MOVE.W	(A1)+,D1                             | get NextB
NEXT:
    CMP.W	D1,D0                                 | is NextA < NextB ?
    BLT.B	ALESS                                 | yes, branch
    BGT.B	BLESS                                 | br if NextB is less
    CMPI.W	#0x7FFF,D0                           | are both at end marker ?
    BEQ.B	SKIP2_EXIT                            | yes, quit
    CMP.W	D3,D2                                 | are AState and BState same ?
    BNE.B	SKIP0                                 | no, skip
    MOVE.W	D0,(A2)+                             | yes, put change
SKIP0:
    MOVE.W	(A0)+,D0                             | get new NextA
    NOT.W	D2                                    | toggle AState
    MOVE.W	(A1)+,D1                             | get new NextB
    NOT.W	D3                                    | toggle BState
    BRA.B	NEXT                                  | loop for more
| ----------------------------------------------------------
|
| ALESS -- A side advanced past B
|
ALESS:
    TST.W	D3                                    | test BState
    BEQ.B	SKIP1                                 | skip if not true
    MOVE.W	D0,(A2)+                             | put NextA
SKIP1:
    MOVE.W	(A0)+,D0                             | get new NextA
    NOT.W	D2                                    | and toggle AState
    BRA.B	NEXT                                  | loop for more
| ----------------------------------------------------------
|
| BLESS -- B side advanced past A
|
BLESS:
    TST.W	D2                                    | test AState
    BEQ.B	SKIP2                                 | skip if not true
    MOVE.W	D1,(A2)+                             | put NextB
SKIP2:
    MOVE.W	(A1)+,D1                             | get new NextB
    NOT.W	D3                                    | and toggle BState
    BRA.B	NEXT                                  | loop for more
| ----------------------------------------------------------
|
| SKIP2_EXIT -- both at end marker, terminate output
|
SKIP2_EXIT:
    MOVE.W	#0x7FFF,(A2)+                        | put end marker into dst
    RTS                                         | return from SKIP2_EXIT
| ---------------------------------------------------------
|
| PROCEDURE InsetScan(src, dst: ScanPtr; dh: INTEGER);
|
| Horizontally inset an inversion scan by dh.
|
| INPUTS:  A0 src, A2 dst, D2 dh
|
| CLOBBERS D0-D1, A0-A2
|
INSETSCAN:
    TST.W	D2                                    | is dh neg ?
    BLT.B	OUTSET                                | yes, outset
| ---------------------------------------------------------------
|
| Get each pair of coords, inset them, and cancel if they cross.
|
INSET:
    CMPI.W	#0x7FFF,(A0)                         | reached end of scan ?
    BEQ.B	OUTOK2_EXIT                           | quit when found
    MOVE.W	(A0)+,D0                             | get left coord
    MOVE.W	(A0)+,D1                             | get right coord
    ADD.W	D2,D0                                 | inset left coordinate
    SUB.W	D2,D1                                 | inset right coordinate
    CMP.W	D1,D0                                 | is left >= right ?
    BGE.B	INSET                                 | yes, skip both
    MOVE.W	D0,(A2)+                             | put left coord to dst
    MOVE.W	D1,(A2)+                             | put right coord to dst
    BRA.B	INSET                                 | loop entire scan
| ------------------------------------------------------------------
|
| Get each pair of coords, outset them, and cancel if they cross.
|
OUTSET:
    MOVEA.W	#0x8001,A1                          | OldRight := -32767
    BRA.B	OUTOK2_LOOP                           | go to loop start
| ----------------------------------------------------------
|
| OUTLOOP -- get a pair of coords, apply outset, merge with prev
|
OUTLOOP:
    MOVE.W	(A0)+,D0                             | get left coord
    MOVE.W	(A0)+,D1                             | get right coord
    ADD.W	D2,D0                                 | add dh to left
    SUB.W	D2,D1                                 | sub dh from right
    CMP.W	A1,D0                                 | is left <= OldRight ?
    BGT.B	OUTOK                                 | no, continue
    SUBQ.W	#0x2,A2                              | merge by dropping previous right
    BRA.B	OUTOK2                                | and continue
| ----------------------------------------------------------
|
| OUTOK -- emit a non-merging pair into dst
|
OUTOK:
    MOVE.W	D0,(A2)+                             | put left coord
OUTOK2:
    MOVE.W	D1,(A2)+                             | put right coord
    MOVEA.W	D1,A1                               | OldRight := right
OUTOK2_LOOP:
    CMPI.W	#0x7FFF,(A0)                         | reached end of scan ?
    BNE.B	OUTLOOP                               | no, loop entire scan
OUTOK2_EXIT:
    MOVE.W	#0x7FFF,(A2)+                        | put terminator
    RTS                                         | return from OUTOK2_EXIT
| ----------------------------------------------------------
|
| EQUAL -- both inputs at same coord; cancel pair
|
EQUAL:
    CMPI.W	#0x7FFF,D0                           | are both at end marker ?
    BEQ.B	OUTOK2_EXIT                           | yes, quit
| --------------------------------------------------------------
|
| LOCAL PROCEDURE XorScan(srcA, srcB, dstC: ScanPtr);
|
| Form the exclusive-or of two inversion scans.
|
| INPUTS:  A0 SrcA, A1 SrcB, A2 DstC
|
| CLOBBERS D0-D1, A0-A2
|
XORSCAN:
    MOVE.W	(A0)+,D0                             | get NextA
    MOVE.W	(A1)+,D1                             | get NextB
INSETSCAN_NEXT:
    CMP.W	D1,D0                                 | which is less, A or B ?
    BEQ.B	EQUAL                                 | the same, so cancel
    BLT.B	INSETSCAN_ALESS                       | A is less
    MOVE.W	D1,(A2)+                             | BLESS: put B to dst
    MOVE.W	(A1)+,D1                             | get next B
    BRA.B	INSETSCAN_NEXT                        | loop for more
| ----------------------------------------------------------
|
| INSETSCAN_ALESS -- A < B: emit A and advance
|
INSETSCAN_ALESS:
    MOVE.W	D0,(A2)+                             | put A to dst
    MOVE.W	(A0)+,D0                             | get next A
    BRA.B	INSETSCAN_NEXT                        | loop for more
