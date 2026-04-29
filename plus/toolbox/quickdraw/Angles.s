| .FUNC AngleFromSlope,1
| .DEF SlopeFromAngle
| -----------------------------------------------------
|
| FUNCTION AngleFromSlope(slope: Fixed): INTEGER;
|
| Scans slope table for angle and returns angle 0..180
|
AngleFromSlope:
        MOVE.L  0x4(SP),D0                      | GET SLOPE
        SMI     D2                              | REMEMBER IF IT WAS NEGATIVE
        BPL.B   SLOPE_POS                       | CONTINUE IF POSITIVE
        NEG.L   D0                              | ELSE MAKE SLOPE POS
SLOPE_POS:
        SUBI.L  #0x1F4,D0                       | SUBTRACT 500 FOR ROUNDING
        MOVE.L  D0,0x4(SP)                      | SAVE ADJUSTED SLOPE ON STACK
        LEA.L   CONTINUE(PC),A0                 | POINT TO TABLE OF SLOPES
        MOVEQ   #-1,D1                          | INIT ANGLE COUNT
SCAN_LOOP:
        ADDQ.W  #0x1,D1                         | BUMP ANGLE
        MOVE    D1,D0                           | D0 = CURRENT ANGLE FOR TABLE LOOKUP
        CLR.L   -(SP)                           | PUSH ZERO FOR TABLE ENTRY
        BRA.B   TABLE_LOOKUP                    | -> GET NEXT TABLE ENTRY

| CONTINUE
CONTINUE:
        MOVE.L  0x8(SP),D0                      | GET SLOPE
        CMP.L   (SP)+,D0                        | SCAN THRU SLOPE TABLE
        BGT.B   SCAN_LOOP                       | SLOPE > TABLE ENTRY, KEEP SCANNING
        MOVE    #180,D0                         | START WITH 180
        SUB     D1,D0                           | CALC 180-ANGLE = 90..180
        TST.B   D2                              | WAS DH POS ?
        BPL.B   DONE                            | NO, RETURN 90..180
        MOVE    D1,D0                           | YES, RETURN 0..90
DONE:
        MOVE.L  (SP)+,(SP)                      | STRIP PARAM
        MOVE    D0,0x4(SP)                      | RETURN ANGLE IN RESULT
        RTS                                     | RETURN TO CALLER

| ----------------------------------------------------------------
|
| FUNCTION SlopeFromAngle(angle: INTEGER): Fixed;
|
| calculate the fixed point slope of a line, DH/DV = -65536 * Tan(angle).
| Input angle is treated MOD 180.
|
SlopeFromAngle:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE    (SP)+,D0                        | GET INTEGER ANGLE
        EXT.L   D0                              | SIGN EXTEND FOR DIVIDE
        DIVS    #180,D0                         | TREAT ANGLE MOD 180
        SWAP    D0                              | GET THE REMAINDER
        TST     D0                              | WAS IT NEGATIVE ?
        BPL.B   MOD_POS                         | NO, CONTINUE
        ADDI    #0xB4,D0                        | ADD 180 TO MAKE POSITIVE
MOD_POS:
        MOVE    #-0x8000,(SP)                   | INIT RESULT HIGH WORD (SIGN FLAG)
| shared entry: map angle 0..180 to tangent table index
TABLE_LOOKUP:
        CMPI    #0x5A,D0                        | ANGLE > 90?
        BLE.B   QUADRANT1                       | NO, FIRST QUADRANT ->
        CLR.W   (SP)                            | CLEAR SIGN (SECOND QUADRANT)
        SUBI    #0xB4,D0                        | ANGLE -= 180
        NEG     D0                              | SUPPLEMENT: 180-ANGLE
QUADRANT1:
        CMPI    #0x2D,D0                        | ANGLE < 45?
        BLT.B   SHARE                           | YES, SMALL SLOPE ->
        ADDQ.W  #0x1,(SP)                       | SLOPE >= 1.0: SET HIGH BYTE
        CMPI    #0x40,D0                        | ANGLE < 64?
        BLT.B   SHARE                           | YES ->
  .short 0x1F7B,0x00DD,0x0001                   | Move.B (table)(D0.W),$1(SP) - APPROX HIGH BYTE FOR LARGE ANGLES
        BPL.B   SHARE                           | SMALL APPROX ->
        ORI.B   #0x7F,(SP)                      | NEAR 90deg: VERY LARGE SLOPE ($7Fxx)
| look up tangent low word from table and apply sign
SHARE:
        ADD     D0,D0                           | WORD INDEX INTO TANGENT TABLE
        MOVE    TAN_TABLE(PC,D0.W),0x2(SP)      | LOW WORD OF SLOPE FROM TABLE
CHECK:
        BCLR    #7,(SP)                         | TEST AND CLEAR SIGN BIT
        BEQ.B   OK3                             | WAS POSITIVE ->
        NEG.L   (SP)                            | NEGATE: SECOND QUADRANT IS NEGATIVE
OK3:
        JMP     (A0)                            | RETURN FIXED-POINT SLOPE ON STACK
| high byte approximation table for slopes at angles 64-90 degrees
  .byte 0x01,0x02,0x02,0x02,0x02,0x02           | ANGLES 64-69
  .byte 0x02,0x02,0x02,0x03,0x03,0x03           | ANGLES 70-75
  .byte 0x03,0x04,0x04,0x04,0x05,0x05           | ANGLES 76-81
  .byte 0x06,0x07,0x08,0x09,0x0B,0x0E           | ANGLES 82-87
  .byte 0x13,0x1C,0x39,0xFF                     | ANGLES 88-91
| TAN_TABLE: tangent table - fixed-point slope values for angles 0-90
| Each word = -65536 * tan(angle), indexed by angle * 2
TAN_TABLE:
  .byte 0x00,0x00,0x04,0x78,0x08,0xF1           | TAN(0),TAN(1),TAN(2)
  .byte 0x0D,0x6B,0x11,0xE7,0x16,0x66           | TAN(3),TAN(4),TAN(5)
  .byte 0x1A,0xE8,0x1F,0x6F,0x23,0xFA           | TAN(6),TAN(7),TAN(8)
  .byte 0x28,0x8C,0x2D,0x24,0x31,0xC3           | TAN(9),TAN(10),TAN(11)
  .byte 0x36,0x6A,0x3B,0x1A,0x3F,0xD4           | TAN(12),TAN(13),TAN(14)
  .byte 0x44,0x98,0x49,0x68,0x4E,0x44           | TAN(15),TAN(16),TAN(17)
  .byte 0x53,0x2E,0x58,0x26,0x5D,0x2D           | TAN(18),TAN(19),TAN(20)
  .byte 0x62,0x45,0x67,0x6E,0x6C,0xAA           | TAN(21),TAN(22),TAN(23)
  .byte 0x71,0xFB,0x77,0x60,0x7C,0xDC           | TAN(24),TAN(25),TAN(26)
  .byte 0x82,0x70,0x88,0x1E,0x8D,0xE7           | TAN(27),TAN(28),TAN(29)
  .byte 0x93,0xCD,0x99,0xD2,0x9F,0xF7           | TAN(30),TAN(31),TAN(32)
  .byte 0xA6,0x40,0xAC,0xAD,0xB3,0x41           | TAN(33),TAN(34),TAN(35)
  .byte 0xB9,0xFF,0xC0,0xE9,0xC8,0x02           | TAN(36),TAN(37),TAN(38)
  .byte 0xCF,0x4E,0xD6,0xCF,0xDE,0x8A           | TAN(39),TAN(40),TAN(41)
  .byte 0xE6,0x81,0xEE,0xB9,0xF7,0x37           | TAN(42),TAN(43),TAN(44)
  .byte 0x00,0x00,0x09,0x19,0x12,0x87           | TAN(45),TAN(46),TAN(47)
  .byte 0x1C,0x51,0x26,0x7F,0x31,0x17           | TAN(48),TAN(49),TAN(50)
  .byte 0x3C,0x22,0x47,0xAA,0x53,0xB9           | TAN(51),TAN(52),TAN(53)
  .byte 0x60,0x5B,0x6D,0x9B,0x7B,0x89           | TAN(54),TAN(55),TAN(56)
  .byte 0x8A,0x35,0x99,0xAF,0xAA,0x0E           | TAN(57),TAN(58),TAN(59)
  .byte 0xBB,0x68,0xCD,0xD6,0xE1,0x77           | TAN(60),TAN(61),TAN(62)
  .byte 0xF6,0x6E,0x0C,0xE1,0x24,0xFE           | TAN(63),TAN(64),TAN(65)
  .byte 0x3E,0xFC,0x5B,0x19,0x79,0x9F           | TAN(66),TAN(67),TAN(68)
  .byte 0x9A,0xE7,0xBF,0x5B,0xE7,0x7A           | TAN(69),TAN(70),TAN(71)
  .byte 0x13,0xE3,0x45,0x56,0x7C,0xC7           | TAN(72),TAN(73),TAN(74)
  .byte 0xBB,0x68,0x02,0xC2,0x54,0xDB           | TAN(75),TAN(76),TAN(77)
  .byte 0xB4,0x62,0x25,0x01,0xAB,0xD9           | TAN(78),TAN(79),TAN(80)
  .byte 0x50,0x51,0x1D,0x88,0x24,0xF3           | TAN(81),TAN(82),TAN(83)
  .byte 0x83,0xAD,0x6E,0x17,0x4C,0xF5           | TAN(84),TAN(85),TAN(86)
  .byte 0x14,0xBD,0xA2,0xD7,0x4A,0x30           | TAN(87),TAN(88),TAN(89)
  .byte 0xFF,0xFF                               | TAN(90) = INFINITY

| .PROC PtToAngle,3
| .REF AngleFromSlope
| --------------------------------------------------------------
|
| PROCEDURE PtToAngle(r: Rect; pt: Point; VAR angle: INTEGER);
|
| Given a rectangle and a point, return the angle subtended by pt.
|
| A6 OFFSETS OF PARAMETERS AFTER LINK:
|
PtToAngle:
.set PARAMSIZE, 12                              | TOTAL BYTES OF PARAMS
.set RECT, PARAMSIZE+8-4                        | ADDR OF RECT
.set PT, RECT-4                                 | POINT
.set ANGLE, PT-4                                | ADDR OF INTEGER;

        LINK    A6,#0                           | NO LOCALS
        MOVEM.L D6-D7/A4,-(SP)                  | SAVE REGS
        MOVE.L  0x10(A6),A4                     | POINT TO RECT
        MOVE    BOTTOM(A4),D0                   | GET RECT BOTTOM
        ADD     (A4),D0                         | ADD RECT TOP
        ASR     #1,D0                           | CENTER.V := (TOP+BOTTOM)/2
        MOVE    0xC(A6),D1                      | GET PT.V
        SUB     D0,D1                           | DV := PT.V - CENTER.V
        MOVE    RIGHT(A4),D0                    | GET RECT RIGHT
        ADD     LEFT(A4),D0                     | ADD RECT LEFT
        ASR     #1,D0                           | CENTER.H := (LEFT+RIGHT)/2
        MOVE    0xE(A6),D7                      | GET PT.H
        SUB     D0,D7                           | DH := PT.H - CENTER.H
        BNE.B   DHOK                            | CONTINUE IF DH <> 0
        TST     D1                              | WAS DV > 0 ?
        BLE.B   ZERO                            | NO, RETURN ANGLE = 0
        MOVE    #180,D0                         | YES, RETURN ANGLE = 180
        BRA.B   PTTOANGLE_DONE                  | STORE AND RETURN

| ----------------------------------------------------------
|
| DHOK
|
DHOK:
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        MOVE    D7,-(SP)                        | PUSH DH
        MOVE    D1,-(SP)                        | PUSH DV
        _FixRatio                               | CALC SLOPE := DH/DV
        MOVE.L  (SP)+,D6                        | GET SLOPE RESULT
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        MOVE    BOTTOM(A4),D0                   | GET RECT BOTTOM
        SUB     (A4),D0                         | SUBTRACT TOP
        MOVE    D0,-(SP)                        | PUSH HEIGHT
        MOVE    RIGHT(A4),D0                    | GET RECT RIGHT
        SUB     LEFT(A4),D0                     | SUBTRACT LEFT
        MOVE    D0,-(SP)                        | PUSH WIDTH
        _FixRatio                               | CALC ASPECT := HT/WD
        MOVE.L  (SP)+,D0                        | GET ASPECT RESULT
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        MOVE.L  D6,-(SP)                        | PUSH SLOPE
        MOVE.L  D0,-(SP)                        | PUSH ASPECT
        _FixMul                                 | CALC SLOPE*ASPECT
        MOVE.L  (SP)+,D0                        | GET RESULT SLOPE2
        CLR.W   -(SP)                           | ROOM FOR FCN RESULT
        MOVE.L  D0,-(SP)                        | PUSH SLOPE2
        JSR     AngleFromSlope(PC)              | SCAN FOR ARCTAN
        MOVE    (SP)+,D0                        | GET RESULT ANGLE
        TST     D7                              | WAS DH POSITIVE ?
        BPL.B   PTTOANGLE_DONE                  | YES, CONTINUE
        ADDI    #0xB4,D0                        | ADD 180 (DH WAS NEGATIVE)
        CMPI    #0x168,D0                       | IS ANGLE = 360 ?
        BNE.B   PTTOANGLE_DONE                  | NO, CONTINUE
ZERO:
        CLR     D0                              | YES, ANGLE := 0
PTTOANGLE_DONE:
        MOVE.L  0x8(A6),A0                      | GET VAR ADDR
        MOVE    D0,(A0)                         | STORE INTO ANGLE
        MOVEM.L (SP)+,D6-D7/A4                  | RESTORE REGS
        UNLK    A6                              | RELEASE LOCAL VARS
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDA    #0xC,SP                         | STRIP 12 BYTES OF PARAMS
        JMP     (A0)                            | RETURN TO CALLER


