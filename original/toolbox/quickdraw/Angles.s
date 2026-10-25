| --> ANGLES.TEXT
|
| SlopeFromAngle (with its tangent table SLOPETBL), AngleFromSlope and
| PtToAngle: angle calculations for arcs.
| Apple source: Angles.a (1983 QuickDraw sources).

| ----------------------------------------------------------------
| FUNCTION SlopeFromAngle(angle: INTEGER): Fixed;
| calculate the fixed point slope of a line, DH/DV = -65536 * Tan(angle).
| Input angle is treated MOD 180.
SlopeFromAngle:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE    (SP)+,D0                        | get angle param
        EXT.L    D0                             | sign-extend for DIVS
        DIVS    #0xB4,D0                        | angle MOD 180 (rem in hi)
        SWAP    D0                              | get remainder
        TST     D0                              | was remainder negative?
        BPL.B   SLOPEFROMANGLE_CONT             | no, continue
        ADDI    #0xB4,D0                        | yes, put in 0..179 range
SLOPEFROMANGLE_CONT:
        LSL     #0x2,D0                         | x4 (long entries in tbl)
        CMPI    #0x168,D0                       | is angle*4 <= 360?
        BLE.B   SLOPEFROMANGLE_CONT_2           | yes, use direct lookup
        SUBI    #0x2D0,D0                       | subtract 720 (mirror)
        NEG     D0                              | reflect for 90..180 half
        .short  0x2EBB, 0x000C                  | MOVE.L SLOPETBL(PC,D0.W),(SP) disp=12
        JMP     (A0)                            | return with positive slope
SLOPEFROMANGLE_CONT_2:
        .short  0x2EBB, 0x0006                  | MOVE.L SLOPETBL(PC,D0.W),(SP) disp=6
        NEG.L   (SP)                            | (SP) = -(SP) (negate for mirrored half)
        JMP     (A0)                            | return with negative slope
SLOPETBL:                                       | SLOPETBL: tan(angle)*65536, angle 0..90
        .long   0x00000000                      | tan(0 deg) * 65536
        .long   0x00000478                      | tan(1 deg) * 65536
        .long   0x000008F1                      | tan(2 deg) * 65536
        .long   0x00000D6B                      | tan(3 deg) * 65536
        .long   0x000011E7                      | tan(4 deg) * 65536
        .long   0x00001666                      | tan(5 deg) * 65536
        .long   0x00001AE8                      | tan(6 deg) * 65536
        .long   0x00001F6F                      | tan(7 deg) * 65536
        .long   0x000023FA                      | tan(8 deg) * 65536
        .long   0x0000288C                      | tan(9 deg) * 65536
        .long   0x00002D24                      | tan(10 deg) * 65536
        .long   0x000031C3                      | tan(11 deg) * 65536
        .long   0x0000366A                      | tan(12 deg) * 65536
        .long   0x00003B1A                      | tan(13 deg) * 65536
        .long   0x00003FD4                      | tan(14 deg) * 65536
        .long   0x00004498                      | tan(15 deg) * 65536
        .long   0x00004968                      | tan(16 deg) * 65536
        .long   0x00004E44                      | tan(17 deg) * 65536
        .long   0x0000532E                      | tan(18 deg) * 65536
        .long   0x00005826                      | tan(19 deg) * 65536
        .long   0x00005D2D                      | tan(20 deg) * 65536
        .long   0x00006245                      | tan(21 deg) * 65536
        .long   0x0000676E                      | tan(22 deg) * 65536
        .long   0x00006CAA                      | tan(23 deg) * 65536
        .long   0x000071FB                      | tan(24 deg) * 65536
        .long   0x00007760                      | tan(25 deg) * 65536
        .long   0x00007CDC                      | tan(26 deg) * 65536
        .long   0x00008270                      | tan(27 deg) * 65536
        .long   0x0000881E                      | tan(28 deg) * 65536
        .long   0x00008DE7                      | tan(29 deg) * 65536
        .long   0x000093CD                      | tan(30 deg) * 65536
        .long   0x000099D2                      | tan(31 deg) * 65536
        .long   0x00009FF7                      | tan(32 deg) * 65536
        .long   0x0000A640                      | tan(33 deg) * 65536
        .long   0x0000ACAD                      | tan(34 deg) * 65536
        .long   0x0000B341                      | tan(35 deg) * 65536
        .long   0x0000B9FF                      | tan(36 deg) * 65536
        .long   0x0000C0E9                      | tan(37 deg) * 65536
        .long   0x0000C802                      | tan(38 deg) * 65536
        .long   0x0000CF4E                      | tan(39 deg) * 65536
        .long   0x0000D6CF                      | tan(40 deg) * 65536
        .long   0x0000DE8A                      | tan(41 deg) * 65536
        .long   0x0000E681                      | tan(42 deg) * 65536
        .long   0x0000EEB9                      | tan(43 deg) * 65536
        .long   0x0000F737                      | tan(44 deg) * 65536
        .long   0x00010000                      | tan(45 deg) * 65536
        .long   0x00010919                      | tan(46 deg) * 65536
        .long   0x00011287                      | tan(47 deg) * 65536
        .long   0x00011C51                      | tan(48 deg) * 65536
        .long   0x0001267F                      | tan(49 deg) * 65536
        .long   0x00013117                      | tan(50 deg) * 65536
        .long   0x00013C22                      | tan(51 deg) * 65536
        .long   0x000147AA                      | tan(52 deg) * 65536
        .long   0x000153B9                      | tan(53 deg) * 65536
        .long   0x0001605B                      | tan(54 deg) * 65536
        .long   0x00016D9B                      | tan(55 deg) * 65536
        .long   0x00017B89                      | tan(56 deg) * 65536
        .long   0x00018A35                      | tan(57 deg) * 65536
        .long   0x000199AF                      | tan(58 deg) * 65536
        .long   0x0001AA0E                      | tan(59 deg) * 65536
        .long   0x0001BB68                      | tan(60 deg) * 65536
        .long   0x0001CDD6                      | tan(61 deg) * 65536
        .long   0x0001E177                      | tan(62 deg) * 65536
        .long   0x0001F66E                      | tan(63 deg) * 65536
        .long   0x00020CE1                      | tan(64 deg) * 65536
        .long   0x000224FE                      | tan(65 deg) * 65536
        .long   0x00023EFC                      | tan(66 deg) * 65536
        .long   0x00025B19                      | tan(67 deg) * 65536
        .long   0x0002799F                      | tan(68 deg) * 65536
        .long   0x00029AE7                      | tan(69 deg) * 65536
        .long   0x0002BF5B                      | tan(70 deg) * 65536
        .long   0x0002E77A                      | tan(71 deg) * 65536
        .long   0x000313E3                      | tan(72 deg) * 65536
        .long   0x00034556                      | tan(73 deg) * 65536
        .long   0x00037CC7                      | tan(74 deg) * 65536
        .long   0x0003BB68                      | tan(75 deg) * 65536
        .long   0x000402C2                      | tan(76 deg) * 65536
        .long   0x000454DB                      | tan(77 deg) * 65536
        .long   0x0004B462                      | tan(78 deg) * 65536
        .long   0x00052501                      | tan(79 deg) * 65536
        .long   0x0005ABD9                      | tan(80 deg) * 65536
        .long   0x00065051                      | tan(81 deg) * 65536
        .long   0x00071D88                      | tan(82 deg) * 65536
        .long   0x000824F3                      | tan(83 deg) * 65536
        .long   0x000983AD                      | tan(84 deg) * 65536
        .long   0x000B6E17                      | tan(85 deg) * 65536
        .long   0x000E4CF5                      | tan(86 deg) * 65536
        .long   0x001314BD                      | tan(87 deg) * 65536
        .long   0x001CA2D7                      | tan(88 deg) * 65536
        .long   0x00394A30                      | tan(89 deg) * 65536
        .long   0x7FFFFFFF                      | tan(90 deg) * 65536

| .FUNC AngleFromSlope,1
| .DEF SlopeFromAngle
| -----------------------------------------------------
| FUNCTION AngleFromSlope(slope: Fixed): INTEGER;
| Scans slope table for angle and returns angle 0..180
AngleFromSlope:
        MOVE.L  4(SP),D0                        | GET SLOPE
        SMI     D2                              | D2 := (N == 1)
        BPL.B   ANGLEFROMSLOPE_CONT             | CONTINUE IF POSITIVE
        NEG.L   D0                              | ELSE MAKE SLOPE POS
ANGLEFROMSLOPE_CONT:
        LEA     SLOPETBL(PC),A0                 | POINT TO TABLE OF SLOPES
        MOVE    #0xB4,D1                        | angle counter init = 180
        SUBI.L  #0x1F4,D0                       | bias slope by -500 for compare
ANGLEFROMSLOPE_SCAN:
        CMP.L   (A0)+,D0                        | compare against next tbl entry
        DBLE    D1,ANGLEFROMSLOPE_SCAN          | dble loop
        MOVE    #0xB4,D0                        | D0 := 180
        SUB     D1,D0                           | CALC 180-ANGLE = 90..180
        TST.B   D2                              | WAS DH POS ?
        BMI.B   ANGLEFROMSLOPE_CONT_2           | neg slope, return 90..180
        MOVE    D1,D0                           | YES, RETURN 0..90
ANGLEFROMSLOPE_CONT_2:
        MOVE.L  (SP)+,(SP)                      | STRIP PARAM
        MOVE    D0,4(SP)                        | return angle as fcn result
        RTS                                     | return from ANGLEFROMSLOPE_CONT_2

| .PROC PtToAngle,3
| .REF AngleFromSlope
| --------------------------------------------------------------
| PROCEDURE PtToAngle(r: Rect; pt: Point; VAR angle: INTEGER);
| Given a rectangle and a point, return the angle subtended by pt.
| Trap _PtToAngle ($A8C3). Plus version: Angles.s 136.
PtToAngle:
        LINK    A6,#0x0                         | set up stack frame
        MOVEM.L D6-D7/A4,-(SP)                  | save regs
        MOVE.L  16(A6),A4                       | A4 := rect ptr
        MOVE    4(A4),D0                        | GET RECT.BOTTOM
        ADD     (A4),D0                         | + rect.top
        ASR     #0x1,D0                         | center.v := (top+bot)/2
        MOVE    12(A6),D1                       | get pt.v
        SUB     D0,D1                           | DV := PT.V - CENTER.V
        MOVE    6(A4),D0                        | get rect.right
        ADD     2(A4),D0                        | + rect.left
        ASR     #0x1,D0                         | center.h := (left+right)/2
        MOVE    14(A6),D7                       | get pt.h
        SUB     D0,D7                           | DH := PT.H - CENTER.H
        BNE.B   PTTOANGLE_NONHORIZ              | CONTINUE IF DH <> 0
        TST     D1                              | WAS DV > 0 ?
        BLE.B   PTTOANGLE_HORIZ                 | NO, RETURN ANGLE = 0
        MOVE    #0xB4,D0                        | GET POLYHANDLE
        BRA.B   PTTOANGLE_DONE                  | skip non-horiz processing
PTTOANGLE_NONHORIZ:
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        MOVE    D7,-(SP)                        | PUSH POLYHANDLE
        MOVE    D1,-(SP)                        | PUSH DV
        JSR     FixRatio(PC)                    | slope := DH / DV (fixed)
        MOVE.L  (SP)+,D6                        | GET SLOPE RESULT
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        MOVE    4(A4),D0                        | get rect.bottom
        SUB     (A4),D0                         | height = bot - top
        MOVE    D0,-(SP)                        | PUSH HEIGHT
        MOVE    6(A4),D0                        | get rect.right
        SUB     2(A4),D0                        | width = right - left
        MOVE    D0,-(SP)                        | PUSH WIDTH
        JSR     FixRatio(PC)                    | aspect := height/width
        MOVE.L  (SP)+,D0                        | GET ASPECT RESULT
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        MOVE.L  D6,-(SP)                        | PUSH SLOPE
        MOVE.L  D0,-(SP)                        | PUSH ASPECT
        JSR     FixMul(PC)                      | slope2 := slope * aspect
        MOVE.L  (SP)+,D0                        | GET RESULT SLOPE2
        CLR     -(SP)                           | room for AngleFromSlope result
        MOVE.L  D0,-(SP)                        | PUSH SLOPE2
        JSR     AngleFromSlope(PC)              | SCAN FOR ARCTAN
        MOVE    (SP)+,D0                        | GET RESULT ANGLE
        TST     D7                              | WAS DH POSITIVE ?
        BPL.B   PTTOANGLE_DONE                  | YES, CONTINUE
        ADDI    #0xB4,D0                        | dh negative: angle += 180
        CMPI    #0x168,D0                       | did we wrap to 360?
        BNE.B   PTTOANGLE_DONE                  | NO, CONTINUE
PTTOANGLE_HORIZ:
        CLR     D0                              | YES, ANGLE := 0
PTTOANGLE_DONE:
        MOVE.L  8(A6),A0                        | GET VAR ADDR
        MOVE    D0,(A0)                         | STORE INTO ANGLE
        MOVEM.L (SP)+,D6-D7/A4                  | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDA.W  #0xC,SP                         | strip 12 bytes of params
        JMP     (A0)                            | RTS
