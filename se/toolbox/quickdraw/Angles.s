| .FUNC AngleFromSlope,1
| .DEF SlopeFromAngle
| -----------------------------------------------------
|
| FUNCTION AngleFromSlope(slope: Fixed): INTEGER;
|
| Scans slope table for angle and returns angle 0..180

| -----------------------------------------------------
|
| FUNCTION AngleFromSlope(slope: Fixed): INTEGER;
|
| Scans slope table for angle and returns angle 0..180
|
ANGLEFROMSLOPE:
    MOVE.L	0x4(A7),D0                           | get slope
    SMI.B	D2                                    | remember if it was negative
    BPL.B	SLOPE_POS                             | continue if positive
    NEG.L	D0                                    | else make slope pos
SLOPE_POS:
    SUBI.L	#0x1F4,D0                            | subtract 500 for rounding
    MOVE.L	D0,0x4(A7)                           | save adjusted slope on stack
    LEA.L	CONTINUE(PC),A0                       | point to table of slopes
    MOVEQ.L	#-0x1,D1                            | init angle count
SCAN_LOOP:
    ADDQ.W	#0x1,D1                              | bump angle
    MOVE.W	D1,D0                                | D0 = current angle for table lookup
    CLR.L	-(A7)                                 | push zero for table entry
    BRA.B	TABLE_LOOKUP                          | -> get next table entry
| CONTINUE
CONTINUE:
    MOVE.L	0x8(A7),D0                           | get slope
    CMP.L	(A7)+,D0                              | scan thru slope table
    BGT.B	SCAN_LOOP                             | slope > table entry, keep scanning
    MOVE.W	#0xB4,D0                             | start with 180
    SUB.W	D1,D0                                 | calc 180-angle = 90..180
    TST.B	D2                                    | was DH pos ?
    BPL.B	DONE                                  | no, return 90..180
    MOVE.W	D1,D0                                | yes, return 0..90
DONE:
    MOVE.L	(A7)+,(A7)                           | strip param
    MOVE.W	D0,0x4(A7)                           | return angle in result
    RTS                                         | return from DONE
| ----------------------------------------------------------------
|
| FUNCTION SlopeFromAngle(angle: INTEGER): Fixed;
|
| Calculate the fixed point slope of a line, DH/DV = -65536 * Tan(angle).
| Input angle is treated MOD 180.
|
SLOPEFROMANGLE:
    MOVEA.L	(A7)+,A0                            | pop return addr
    MOVE.W	(A7)+,D0                             | get integer angle
    EXT.L	D0                                    | sign extend for divide
    DIVS.W	#0xB4,D0                             | treat angle MOD 180
    SWAP.W	D0                                   | get the remainder
    TST.W	D0                                    | was it negative ?
    BPL.B	MOD_POS                               | no, continue
    ADDI.W	#0xB4,D0                             | add 180 to make positive
MOD_POS:
    MOVE.W	#0x8000,(A7)                         | init result high word (sign flag)
| shared entry: map angle 0..180 to tangent table index
TABLE_LOOKUP:
    CMPI.W	#0x5A,D0                             | angle > 90 ?
    BLE.B	QUADRANT1                             | no, first quadrant ->
    CLR.W	(A7)                                  | clear sign (second quadrant)
    SUBI.W	#0xB4,D0                             | angle -= 180
    NEG.W	D0                                    | supplement: 180-angle
QUADRANT1:
    CMPI.W	#0x2D,D0                             | angle < 45 ?
    BLT.B	SHARE                                 | yes, small slope ->
    ADDQ.W	#0x1,(A7)                            | slope >= 1.0: set high byte
    CMPI.W	#0x40,D0                             | angle < 64 ?
    BLT.B	SHARE                                 | yes ->
    .byte 0x1F,0x7B,0x00,0xDD,0x00,0x01         | Move.B DT65(D0.W),$1(A7) -- approx high byte for large angles
    BPL.B	SHARE                                 | small approx ->
    ORI.B	#0x7F,(A7)                            | near 90deg: very large slope ($7Fxx)
| look up tangent low word from table and apply sign
SHARE:
    ADD.W	D0,D0                                 | word index into tangent table
    MOVE.W	TAN_TABLE(PC,D0.W),0x2(A7)           | low word of slope from table
CHECK:
    BCLR	#0x7,(A7)                              | test and clear sign bit
    BEQ.B	OK3                                   | was positive ->
    NEG.L	(A7)                                  | negate: second quadrant is negative
OK3:
    JMP	(A0)                                    | return fixed-point slope on stack
| -----------------------------------------------------------------------------
|
| High-byte approximation table for slopes at angles 64-90 degrees.
| Indexed by D0 (angle - 64) read inline by the .byte 0x1F,0x7B,...
| (Move.B DT65(D0.W),$1(A7)) instruction in SLOPEFROMANGLE above.
|
| Layout: 28 bytes total
|   Angles 64-69:  01 02 02 02 02 02
|   Angles 70-75:  02 02 02 03 03 03
|   Angles 76-81:  03 04 04 04 05 05
|   Angles 82-87:  06 07 08 09 0B 0E
|   Angles 88-91:  13 1C 39 FF
|
    .long	0x01020202
    .long	0x02020202
    .long	0x02030303
    .long	0x03040404
    .long	0x05050607
    .long	0x08090B0E
    .long	0x131C39FF
| -----------------------------------------------------------------------------
|
| TAN_TABLE: tangent table -- fixed-point slope values for angles 0..90
| Each word = -65536 * tan(angle), indexed by angle * 2.
| Used by SLOPEFROMANGLE via "MOVE.W TAN_TABLE(PC,D0.W),0x2(A7)".
|
| Layout: 91 words = 182 bytes (encoded here as 45 longs + 1 word):
|   tan(0..2), tan(3..5), tan(6..8), tan(9..11), tan(12..14), tan(15..17),
|   tan(18..20), tan(21..23), tan(24..26), tan(27..29), tan(30..32),
|   tan(33..35), tan(36..38), tan(39..41), tan(42..44), tan(45..47),
|   tan(48..50), tan(51..53), tan(54..56), tan(57..59), tan(60..62),
|   tan(63..65), tan(66..68), tan(69..71), tan(72..74), tan(75..77),
|   tan(78..80), tan(81..83), tan(84..86), tan(87..89), tan(90)=infinity.
|
TAN_TABLE:
    .long	0x00000478
    .long	0x08F10D6B
    .long	0x11E71666
    .long	0x1AE81F6F
    .long	0x23FA288C
    .long	0x2D2431C3
    .long	0x366A3B1A
    .long	0x3FD44498
    .long	0x49684E44
    .long	0x532E5826
    .long	0x5D2D6245
    .long	0x676E6CAA
    .long	0x71FB7760
    .long	0x7CDC8270
    .long	0x881E8DE7
    .long	0x93CD99D2
    .long	0x9FF7A640
    .long	0xACADB341
    .long	0xB9FFC0E9
    .long	0xC802CF4E
    .long	0xD6CFDE8A
    .long	0xE681EEB9
    .long	0xF7370000
    .long	0x09191287
    .long	0x1C51267F
    .long	0x31173C22
    .long	0x47AA53B9
    .long	0x605B6D9B
    .long	0x7B898A35
    .long	0x99AFAA0E
    .long	0xBB68CDD6
    .long	0xE177F66E
    .long	0x0CE124FE
    .long	0x3EFC5B19
    .long	0x799F9AE7
    .long	0xBF5BE77A
    .long	0x13E34556
    .long	0x7CC7BB68
    .long	0x02C254DB
    .long	0xB4622501
    .long	0xABD95051
    .long	0x1D8824F3
    .long	0x83AD6E17
    .long	0x4CF514BD
    .long	0xA2D74A30
    .short	0xFFFF                               | tan(90) = infinity
| --------------------------------------------------------------
|
| PROCEDURE PtToAngle(r: Rect; pt: Point; VAR angle: INTEGER);
|
| Given a rectangle and a point, return the angle subtended by pt.
|
| A6 offsets of parameters after LINK:
|   RECT  = 0x10  (LONG: addr of Rect)
|   PT    = 0xC   (LONG: Point as VFirst)
|   ANGLE = 0x8   (LONG: addr of INTEGER)
|
PTTOANGLE:
    LINK	A6,#0x0                                | no locals
    MOVEM.L	D6-D7/A4,-(A7)                      | save regs
    MOVEA.L	0x10(A6),A4                         | point to rect
    MOVE.W	0x4(A4),D0                           | get rect bottom
    ADD.W	(A4),D0                               | add rect top
    ASR.W	#0x1,D0                               | center.v := (top+bottom)/2
    MOVE.W	0xC(A6),D1                           | get pt.v
    SUB.W	D0,D1                                 | DV := pt.v - center.v
    MOVE.W	0x6(A4),D0                           | get rect right
    ADD.W	0x2(A4),D0                            | add rect left
    ASR.W	#0x1,D0                               | center.h := (left+right)/2
    MOVE.W	0xE(A6),D7                           | get pt.h
    SUB.W	D0,D7                                 | DH := pt.h - center.h
    BNE.B	DHOK                                  | continue if DH <> 0
    TST.W	D1                                    | was DV > 0 ?
    BLE.B	ZERO                                  | no, return angle = 0
    MOVE.W	#0xB4,D0                             | yes, return angle = 180
    BRA.B	PTTOANGLE_DONE                        | store and return
| ----------------------------------------------------------
|
| DHOK -- DH non-zero: compute slope = (DH/DV) * (height/width),
| feed to AngleFromSlope, then fix up sign for DH < 0.
|
DHOK:
    CLR.L	-(A7)                                 | room for fcn result
    MOVE.W	D7,-(A7)                             | push DH
    MOVE.W	D1,-(A7)                             | push DV
    _FixRatio                                   | calc slope := DH/DV
    MOVE.L	(A7)+,D6                             | get slope result
    CLR.L	-(A7)                                 | room for fcn result
    MOVE.W	0x4(A4),D0                           | get rect bottom
    SUB.W	(A4),D0                               | subtract top
    MOVE.W	D0,-(A7)                             | push height
    MOVE.W	0x6(A4),D0                           | get rect right
    SUB.W	0x2(A4),D0                            | subtract left
    MOVE.W	D0,-(A7)                             | push width
    _FixRatio                                   | calc aspect := ht/wd
    MOVE.L	(A7)+,D0                             | get aspect result
    CLR.L	-(A7)                                 | room for fcn result
    MOVE.L	D6,-(A7)                             | push slope
    MOVE.L	D0,-(A7)                             | push aspect
    _FixMul                                     | calc slope*aspect
    MOVE.L	(A7)+,D0                             | get result slope2
    CLR.W	-(A7)                                 | room for fcn result
    MOVE.L	D0,-(A7)                             | push slope2
    JSR	ANGLEFROMSLOPE(PC)                      | scan for arctan
    MOVE.W	(A7)+,D0                             | get result angle
    TST.W	D7                                    | was DH positive ?
    BPL.B	PTTOANGLE_DONE                        | yes, continue
    ADDI.W	#0xB4,D0                             | add 180 (DH was negative)
    CMPI.W	#0x168,D0                            | is angle = 360 ?
    BNE.B	PTTOANGLE_DONE                        | no, continue
ZERO:
    CLR.W	D0                                    | yes, angle := 0
PTTOANGLE_DONE:
    MOVEA.L	0x8(A6),A0                          | get VAR addr
    MOVE.W	D0,(A0)                              | store into angle
    MOVEM.L	(A7)+,D6-D7/A4                      | restore regs
    UNLK	A6                                     | release local vars
    MOVEA.L	(A7)+,A0                            | pop return address
    ADDA.W	#0xC,A7                              | strip 12 bytes of params
    JMP	(A0)                                    | tail-call return from PTTOANGLE_DONE via A0
