| -------------------------------------------------------------
|
| --> UTIL.TEXT
|
| SMALL UTILITY ROUTINES USED BY QuickDraw.
|

| .FUNC BitNot,1
| -----------------------------------------------------------
|
| Function BitNot(long: LongInt): LongInt;
|
BitNot:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        NOT.L   (SP)                            | INVERT LONG
        MOVE.L  (SP)+,(SP)                      | STORE INTO RESULT
        JMP     (A0)                            | AND RETURN

| .FUNC BitAnd,2
| .DEF BitXor,BitOr,BitShift
| -----------------------------------------------------------
|
| Function BitAnd(long1,long2: LongInt): LongInt;
|
| Called during boot (25,880 times in 30s trace).
BitAnd:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,D0                        | GET ONE LONG
        AND.L   (SP)+,D0                        | AND IT WITH THE OTHER
        BRA.B   BITSHIFT_DONE                   | AND STORE RESULT

| -----------------------------------------------------------
|
| Function BitXor(long1,long2: LongInt): LongInt;
|
BitXor:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,D0                        | GET ONE LONG
        MOVE.L  (SP)+,D1                        | GET THE SECOND
        EOR.L   D1,D0                           | XOR BOTH
        BRA.B   BITSHIFT_DONE                   | AND STORE RESULT

| -----------------------------------------------------------
|
| Function BitOr(long1,long2: LongInt): LongInt;
|
| Called during boot.
BitOr:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,D0                        | GET ONE LONG
        OR.L    (SP)+,D0                        | OR IT WITH THE OTHER
        BRA.B   BITSHIFT_DONE                   | AND STORE RESULT

| -----------------------------------------------------------
|
| Function BitShift(long: LongInt; count: INTEGER): LongInt;
|
| positive count --> shift left.
| negative count --> shift right.
|
BitShift:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE    (SP)+,D1                        | GET COUNT
        BPL.B   SHLEFT                          | SHIFT LEFT IF POSITIVE
        NEG     D1                              | MAKE COUNT POSITIVE
        MOVE.L  (SP)+,D0                        | GET LONG
        LSR.L   D1,D0                           | SHIFT IT RIGHT
        BRA.B   BITSHIFT_DONE                   | AND STORE RESULT

| ----------------------------------------------------------
|
| SHLEFT
|
SHLEFT:
        MOVE.L  (SP)+,D0                        | GET LONG
        LSL.L   D1,D0                           | SHIFT IT LEFT
BITSHIFT_DONE:
        MOVE.L  D0,(SP)                         | DONE: STORE THE RESULT
        JMP     (A0)                            | AND RETURN

| .FUNC BitTst,2
| .DEF BitSet,BitClr
| ---------------------------------------------------------
|
| FUNCTION BitTst(bytePtr: Ptr; bitNum: LongInt): BOOLEAN;
|
| Called during boot.
BitTst:
        BSR.B   BITCLR_CONT                     | JUMP TO SHARED POINTER SETUP
        MOVE.L  (SP)+,A1                        | GET PTR
        BTST    D0,0x0(A1,D1.L)                 | TEST THE BIT
        SNE     (SP)                            | SET OR CLEAR RESULT
        NEG.B   (SP)                            | CONVERT -1 TO 1
        JMP     (A0)                            | RETURN

| ---------------------------------------------------------
|
| PROCEDURE BitSet(bytePtr: Ptr; bitNum: LongInt);
|
BitSet:
        BSR.B   BITCLR_CONT                     | JMP TO SHARED POINTER SETUP
        MOVE.L  (SP)+,A1                        | GET PTR
        BSET    D0,0x0(A1,D1.L)                 | SET THE BIT
        JMP     (A0)                            | RETURN TO CALLER

| ---------------------------------------------------------
|
| PROCEDURE BitClr(bytePtr: Ptr; bitNum: LongInt);
|
BitClr:
        BSR.B   BITCLR_CONT                     | JMP TO SHARED POINTER SETUP
        MOVE.L  (SP)+,A1                        | GET PTR
        BCLR    D0,0x0(A1,D1.L)                 | SET THE BIT
        JMP     (A0)                            | RETURN TO CALLER


| ----------------------------------------------------------
|
| BITCLR_CONT
|
| Called during boot.
BITCLR_CONT:
        MOVE.L  (SP)+,A1                        | SHARE
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,D1                        | GET BITNUM
        MOVE    D1,D0                           | COPY IT
        ASR.L   #3,D1                           | CONVERT BITS TO BYTES
        NOT     D0                              | REVERSE BIT SENSE
        JMP     (A1)                            | RETURN TO CALLER

| .FUNC Random,0
| --------------------------------------------------------------
|
| FUNCTION Random: INTEGER;
|
| returns a signed 16 bit number, and updates unsigned 32 bit randSeed.
|
| recursion is randSeed := (randSeed * 16807) MOD 2147483647.
|
| See paper by Linus Schrage, A More Portable Fortran Random Number Generator
| ACM Trans Math Software Vol 5, No. 2, June 1979, Pages 132-138.
|
| Clobbers D0-D2, A0
|
|
| GET LO 16 BITS OF SEED AND FORM LO PRODUCT
| xalo := A * LoWord(seed)
|
Random:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE    #16807,D0                       | GET A = 7^5
        MOVE    D0,D2                           | GET A = 7^5
        MULU    -0x7C(A0),D0                    | CALC LO PRODUCT = XALO

|
| FORM 31 HIGHEST BITS OF LO PRODUCT
| fhi:=HiWord(seed) * ORD4(a) + HiWord(xalo);
|
        MOVE.L  D0,D1                           | COPY xalo
        CLR.W   D1                              | CLEAR OUT HI WORD
        SWAP    D1                              | GET HiWord(xalo) as a long
        MULU    RANDSEED(A0),D2                 | MULT BY HiWord(seed)
        ADD.L   D1,D2                           | ADD LEFTLO = FHI

|
| GET OVERFLOW PAST 31ST BIT OF FULL PRODUCT
| k:=fhi DIV 32768;
|
        MOVE.L  D2,D1                           | COPY FHI
        ADD.L   D1,D1                           | CALC 2 TIMES FHI
        CLR.W   D1                              | CLEAR OUT HI WORD
        SWAP    D1                              | CALC FHI SHIFTED RIGHT 15 FOR K
        ANDI.L  #0xFFFF,D0                      | GET LO WORD XALO
        SUBI.L  #0x7FFFFFFF,D0                  | SUBTRACT P = 2^31-1
        ANDI.L  #0x7FFF,D2                      | BITAND(FHI,$00007FFF)

|
| ASSEMBLE ALL THE PARTS AND PRE-SUBTRACT P
| seed:=((BitAnd(XALO,$0000FFFF) - P) + BitAnd(fhi,$00007FFF) * b16) + K;
|
        SWAP    D2                              | TIMES 64K
        ADD.L   D1,D2                           | PLUS K
        ADD.L   D2,D0                           | CALC TOTAL

|
| IF seed < 0 THEN seed:=seed+p;
|
        BPL.B   RANDOM_UPDATE                   | BRANCH IF SEED POSITIVE
        ADDI.L  #0x7FFFFFFF,D0                  | ADD P TO NEGATIVE SEED
RANDOM_UPDATE:
        MOVE.L  D0,RANDSEED(A0)                 | UPDATE SEED
        CMPI    #-0x8000,D0                     | IS NUMBER -32768 ?
        BNE.B   RANDOM_UPDATE_NO                | NO, CONTINUE
        CLR     D0                              | YES, RETURN ZERO INSTEAD
RANDOM_UPDATE_NO:
        MOVE    D0,0x4(SP)                      | RETURN LO WORD AS RESULT
        RTS                                     | RETURN TO CALLER

| .PROC ForeColor,1
| .DEF BackColor,PortLong,ColorBit,PortWord
| --------------------------------------------------------------
|
| PROCEDURE ForeColor(color: LongInt);
ForeColor:
        MOVEQ.L #0x50,D0                        | GET OFFSET TO FGCOLOR
        BRA.B   L_mPortLong                     | INSTALL A LONG

| --------------------------------------------------------------
|
| PROCEDURE BackColor(color: LongInt);
|
| BackColor
|
| FALL THRU INTO PORTLONG
|
| -------------------------------------------------------
|
| PROCEDURE PortLong(long: LongInt);
| INSTALL A LONG INTO CURRENT GRAFPORT. ENTER WITH OFFSET IN D0
|
| PortLong
BackColor:
        MOVEQ.L #0x54,D0                        | GET OFFSET TO BKCOLOR
L_mPortLong:
        MOVE.L  (SP)+,A1                        | POP RETURN ADDR
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | POINT TO THEPORT
        MOVE.L  (SP)+,0x0(A0,D0.W)              | INSTALL LONG INTO THEPORT
        JMP     (A1)                            | AND RETURN

| --------------------------------------------------------------
|
| PROCEDURE ColorBit(whichBit: INTEGER);
|
| ColorBit
| FALL THRU INTO PORTWORD
ColorBit:
        MOVEQ.L #0x58,D0                        | GET OFFSET TO COLRBIT

| -------------------------------------------------------
|
| PROCEDURE PortWord(word: INTEGER);
| INSTALL A WORD INTO CURRENT GRAFPORT. ENTER WITH OFFSET IN D0
|
| PortWord

| .PROC GetMaskTab,0
| .DEF LeftMask,RightMask,BitMask,MaskTab
| ----------------------------------------------------------
|
| ASSEMBLY LANGUAGE CALLABLE PROCEDURES LEFTMASK, RIGHTMASK, AND BITMASK:
|
| ENTER WITH COORDINATE IN D0, RETURNS WITH 16 BIT MASK IN D0
| NO OTHER REGISTERS ALTERED.
|
| Called during boot.
L_mPortWord:
        MOVE.L  (SP)+,A1                        | POP RETURN ADDR
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | POINT TO THEPORT
        MOVE    (SP)+,0x0(A0,D0.W)              | INSTALL WORD INTO THEPORT
        JMP     (A1)                            | AND RETURN

| GetMaskTable -- trap handler for _RealColor ($A836).
| ----------------------------------------------------------
|
| _RealColor ($A836)
|
GetMaskTable:
        LEA.L   DT_mMaskTab(PC),A0              | POINT TO MASK TABLE
        RTS                                     | RETURN TO CALLER

| ----------------------------------------------------------
|
| Left Mask
|
| Called during boot.
LeftMask:
        ANDI    #0xF,D0                         | TREAT MOD 16

| RTS ;AND RETURN

| LeftMask
        ADD     D0,D0                           | DOUBLE FOR TABLE
        MOVE    DT_MMASKTAB_CONT(PC,D0.W),D0    | GET LEFTMASK
        RTS                                     | RETURN TO CALLER

| ----------------------------------------------------------
|
| Right Mask
|
| Called during boot.
RightMask:
        ANDI    #0xF,D0                         | TREAT MOD 16

| RTS

| RIGHTMASK
        ADD     D0,D0                           | DOUBLE FOR TABLE
        MOVE    DT_mMaskTab(PC,D0.W),D0         | GET RIGHT MASK
        RTS                                     | RETURN TO CALLER

| ----------------------------------------------------------
|
| Bit Mask
|
BitMask:
        ANDI    #0xF,D0                         | TREAT MOD 16

| RTS
        ADD     D0,D0                           | DOUBLE FOR TABLE
        MOVE    DT_MMASKTAB_CONT_2(PC,D0.W),D0  | GET BITMASK
        RTS                                     | RETURN TO CALLER

| ----------------------------------------------------------
|
| DT_m Mask Tab
|
DT_mMaskTab:
  .byte 0x00,0x00,0x80,0x00,0xC0,0x00           | LEFT MASKS: BITS 0-2
  .byte 0xE0,0x00,0xF0,0x00,0xF8,0x00           | LEFT MASKS: BITS 3-5
  .byte 0xFC,0x00,0xFE,0x00,0xFF,0x00           | LEFT MASKS: BITS 6-8
  .byte 0xFF,0x80,0xFF,0xC0,0xFF,0xE0           | LEFT MASKS: BITS 9-11
  .byte 0xFF,0xF0,0xFF,0xF8,0xFF,0xFC           | LEFT MASKS: BITS 12-14
  .byte 0xFF,0xFE                               | LEFT MASK: BIT 15
DT_MMASKTAB_CONT:
  .byte 0xFF,0xFF,0x7F,0xFF,0x3F,0xFF           | RIGHT MASKS: BITS 0-2
  .byte 0x1F,0xFF,0x0F,0xFF,0x07,0xFF           | RIGHT MASKS: BITS 3-5
  .byte 0x03,0xFF,0x01,0xFF,0x00,0xFF           | RIGHT MASKS: BITS 6-8
  .byte 0x00,0x7F,0x00,0x3F,0x00,0x1F           | RIGHT MASKS: BITS 9-11
  .byte 0x00,0x0F,0x00,0x07,0x00,0x03           | RIGHT MASKS: BITS 12-14
  .byte 0x00,0x01                               | RIGHT MASK: BIT 15
DT_MMASKTAB_CONT_2:
  .byte 0x80,0x00,0x40,0x00,0x20,0x00           | SINGLE BIT MASKS: BITS 0-2
  .byte 0x10,0x00,0x08,0x00,0x04,0x00           | SINGLE BIT MASKS: BITS 3-5
  .byte 0x02,0x00,0x01,0x00,0x00,0x80           | SINGLE BIT MASKS: BITS 6-8
  .byte 0x00,0x40,0x00,0x20,0x00,0x10           | SINGLE BIT MASKS: BITS 9-11
  .byte 0x00,0x08,0x00,0x04,0x00,0x02           | SINGLE BIT MASKS: BITS 12-14
  .byte 0x00,0x01                               | SINGLE BIT MASK: BIT 15

| .PROC PatExpand,0
| ----------------------------------------------------------
|
| EXPAND AN 8 BYTE PATTERN OUT TO 16 LONGS.
|
| CALLED ONLY FROM BITBLT,RGNBLT,DRAWLINE,DRAWARC.
|
| INPUTS: A0: POINTS TO 8 BYTE PATTERN
| A1: POINTS TO 16 LONGS OF DESTINATION
| A5: PASCAL GLOBAL PTR
| D2: HORIZONTAL GLOBAL-LOCAL OFFSET USED FOR PRE-ROTATE
| D7: -1 TO INVERT, ELSE 0
| patStretch AND PATALIGN
|
| OUTPUTS: 16 LONGS OF EXPANDED PATTERN
|
| CLOBBERS: D0,D1,D2,A0,A1
|
| Called during boot.
PatExpand:
        LINK    A6,#-0x10                       | ALLOCATE STACK FRAME
.set PARAMSIZE, 0                               | NO PARAMS (REGS ONLY)
.set TWOPAT, -16                                | ROOM FOR TWO COPIES OF PAT
.set VARSIZE, TWOPAT                            | TOTAL BYTES OF LOCAL VARS

        MOVE.L  A4,-(SP)                        | SAVE REGS
        MOVE.L  (A5),A4                         | POINT TO QUICKDRAW GLOBALS

|
| IF PATALIGN VERT NON-ZERO, COPY PAT TWICE AND REPLACE A0
|
        MOVEQ   #7,D0                           | MASK FOR 3 LO BITS
        AND     PATALIGN(A4),D0                 | GET PATALIGN MOD 8
        BEQ.B   PATEXPAND_SKIP                  | SKIP IF ZERO
        MOVE.L  (A0),-0x10(A6)                  | MAKE TWO COPIES OF PATTERN
        MOVE.L  (A0)+,-0x8(A6)                  | MAKE SECOND COPY OF PATTERN
        MOVE.L  (A0),-0xC(A6)                   | MAKE THIRD COPY OF PATTERN
        MOVE.L  (A0),-0x4(A6)                   | MAKE FOURTH COPY OF PATTERN
        LEA.L   -0x10(A6),A0                    | POINT TO PATTERN BUFFER
        ADD     D0,A0                           | OFFSET BY PATALIGN
PATEXPAND_SKIP:
        ADD     -0xA6(A4),D2                    | ADJUST FOR PATALIGN HORIZ

| VERTOK
        MOVEQ   #7,D1                           | INIT COUNT OF 8 BYTES
        AND     D1,D2                           | TREAT SHIFTCOUNT MOD 8
        MOVE.L  (A4),A4                         | GET CURRENT GRAFPORT
        MOVE    PATSTRETCH(A4),D0               | GET patStretch
        CMPI    #0x2,D0                         | IS PATSTRETCH = 2 ?
        BEQ.B   DOUBLE                          | YES, DOUBLE
        CMPI    #-0x2,D0                        | IS PATSTRETCH = -2 ?
        BEQ.B   THIN                            | YES, STRETCH THIN

| ANY OTHER, USE NORMAL

| ---------------------------------------------------------
|
| NORMAL PATTERN. SIMPLY REPLICATE THE 8 BY 8 PATTERN.
|
| Called during boot (3,160 times in 30s trace).
NORMAL:
        MOVE.B  (A0)+,D0                        | GET A BYTE OF PATTERN
        EOR.B   D7,D0                           | INVERT IT IF MODE BIT 2
        ROL.B   D2,D0                           | ALIGN TO LOCAL COORDS
        MOVE.B  D0,(A1)+                        | PUT ONE BYTE
        MOVE.B  D0,(A1)+                        | PUT ANOTHER TO MAKE A WORD
        MOVE    -0x2(A1),(A1)+                  | STRETCH WORD OUT TO LONG
        MOVE.L  -0x4(A1),0x1C(A1)               | DUPLICATE 8 SCANS LATER
        DBF     D1,NORMAL                       | LOOP ALL 8 INPUT BYTES
        BRA.B   PATEXPAND_DONE                  | DONE WITH NORMAL PATTERN

| -----------------------------------------------------------
|
| STRETCHED BY TWO: DOUBLE EACH BIT HORIZONTALLY AND VERTICALLY
|
DOUBLE:
        CLR     D0                              | CLEAR OUT HI BYTE
DLOOP:
        MOVE.B  (A0)+,D0                        | GET A BYTE OF PATTERN
        EOR.B   D7,D0                           | INVERT IT IF MODE BIT 2
        ROL.B   D2,D0                           | ALIGN TO LOCAL COORDS
        MOVE.B  D0,-(SP)                        | STASH FOR A WHILE
        LSR.B   #4,D0                           | GET HI NIBBLE
        MOVE.B  PATEXPAND_DONE_CONT(PC,D0.W),(A1)+ | PUT ONE BYTE
        MOVEQ.L #0xF,D0                         | MASK FOR LO NIBBLE
        AND.B   (SP)+,D0                        | GET THE LO NIBBLE
        MOVE.B  PATEXPAND_DONE_CONT(PC,D0.W),(A1)+ | PUT ANOTHER TO MAKE A WORD
        MOVE    -0x2(A1),(A1)+                  | STRETCH WORD OUT TO LONG
        MOVE.L  -0x4(A1),(A1)+                  | STRETCH LONG TO TWO LONGS
        DBF     D1,DLOOP                        | LOOP ALL 8 INPUT BYTES
        BRA.B   PATEXPAND_DONE                  | DONE WITH DOUBLED PATTERN

| -----------------------------------------------------------
|
| STRETCH BY TWO AND THIN OUT THE BITS. ADD EXTRA WHITE DOTS.
|
THIN:
        CLR     D0                              | CLEAR OUT HI BYTE
THINLP:
        MOVE.B  (A0)+,D0                        | GET A BYTE OF PATTERN
        EOR.B   D7,D0                           | INVERT IT IF MODE BIT 2
        ROL.B   D2,D0                           | ALIGN TO LOCAL COORDS
        MOVE.B  D0,-(SP)                        | STASH FOR A WHILE
        LSR.B   #4,D0                           | GET HI NIBBLE
        MOVE.B  PATEXPAND_DONE_CONT_2(PC,D0.W),(A1)+ | PUT ONE BYTE
        MOVEQ.L #0xF,D0                         | MASK FOR LO NIBBLE
        AND.B   (SP)+,D0                        | GET THE LO NIBBLE
        MOVE.B  PATEXPAND_DONE_CONT_2(PC,D0.W),(A1)+ | PUT ANOTHER TO MAKE A WORD
        MOVE    -0x2(A1),(A1)+                  | STRETCH WORD OUT TO LONG
        CLR.L   (A1)+                           | STRETCH LONG TO TWO LONGS
        DBF     D1,THINLP                       | LOOP ALL 8 INPUT BYTES
PATEXPAND_DONE:
        MOVE.L  (SP)+,A4                        | DONE: RESTORE REG
        UNLK    A6                              | RELEASE STACK FRAME
        RTS                                     | RETURN TO CALLER

| ----------------------------------------------------------
|
| PATEXPAND_DONE_CONT
|
PATEXPAND_DONE_CONT:
  .byte 0x00,0x03,0x0C,0x0F,0x30,0x33           | DOUBLE: NIBBLE EXPAND TABLE LO
  .byte 0x3C,0x3F,0xC0,0xC3,0xCC,0xCF           | DOUBLE: NIBBLE EXPAND TABLE MID
  .byte 0xF0,0xF3,0xFC,0xFF                     | DOUBLE: NIBBLE EXPAND TABLE HI
PATEXPAND_DONE_CONT_2:
  .byte 0x00,0x01,0x04,0x05,0x10,0x11           | TRIPLE: NIBBLE EXPAND TABLE LO
  .byte 0x14,0x15,0x40,0x41,0x44,0x45           | TRIPLE: NIBBLE EXPAND TABLE MID
  .byte 0x50,0x51,0x54,0x55                     | TRIPLE: NIBBLE EXPAND TABLE HI

| .PROC ColorMap,2
| PROCEDURE ColorMap(mode: INTEGER, pat: Pattern);
|
| ADJUST INPUT MODE AND PATTERN TO ACCOMPLISH COLOR SEPARATION.
| Returns (altered) mode and pat on the stack where they were.
| PRESERVES ALL REGISTERS.
|
| Called during boot.
ColorMap:
        MOVEM.L D0-D3/A0,-(SP)                  | SAVE REGS
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE.L  A0,D0                           | IS THEPORT NIL ?
        BEQ.B   COLOROK                         | YES, LEAVE COLOR ALONE
        BTST    #0,D0                           | IS THEPORT ODD ?
        BNE.B   COLOROK                         | YES, LEAVE COLOR ALONE
        MOVE    COLRBIT(A0),D2                  | GET COLOR BIT SELECT
        BMI.B   COLOROK                         | COLORBIT = -1 MEANS NO COLOR
        MOVE    0x1C(SP),D3                     | GET INPUT MODE
        MOVEQ   #3,D0                           | MASK FOR BOTTOM 2 BITS
        AND     D3,D0                           | GET 2 BITS OF MODE
        BEQ.B   COLORMAP_COPY                   | BR IF COPY MODE
        CMPI    #0x2,D0                         | IS IT SOME KIND OF XOR ?

|
| THE XOR MODES DEPEND ON NEITHER FOREGROUND OR BACKGROUND COLOR
|
        BEQ.B   COLOROK                         | YES, THEY DON'T CHANGE
        BGT.B   BICMODE                         | BRANCH IF BIC

| ELSE MUST BE OR
|
| THE OR MODES DEPEND ONLY ON THE FOREGROUND COLOR
|
| Called during boot.
ORMODE:
        MOVE.L  FGCOLOR(A0),D1                  | GET FOREGROUND COLOR
COLORMAP_SHARE:
        BTST    D2,D1                           | SHARE: TEST FOREGROUND COLOR BIT
        BNE.B   COLOROK                         | NO CHANGE IF FG TRUE
        EORI    #0x2,D3                         | INVERT MODE BIT 2
        BRA.B   NEWMODE                         | UPDATE MODE AND QUIT

|
| THE BIC MODES DEPEND ONLY ON THE BACKGROUND COLOR
|
| Called during boot.
BICMODE:
        MOVE.L  BKCOLOR(A0),D1                  | GET BACKGROUND COLOR
        NOT.L   D1                              | INVERT IT
        BRA.B   COLORMAP_SHARE                  | AND SHARE CODE

|
| THE COPY MODES DEPEND ON BOTH FOREGOUND AND BACKGROUND
|
| Called during boot.
COLORMAP_COPY:
        MOVE.L  FGCOLOR(A0),D0                  | COPY: GET FOREGROUND COLOR
        MOVE.L  BKCOLOR(A0),D1                  | GET BACKGROUND COLOR
        BTST    D2,D0                           | TEST FOREGROUND COLOR BIT
        BEQ.B   FORE0                           | BRANCH IF IT'S ZERO
FORE1:
        BTST    D2,D1                           | TEST BACKGROUND COLOR BIT
        BEQ.B   COLOROK                         | NO CHANGE IF BKGND FALSE
        MOVEQ   #8,D3                           | ELSE REPLACE MODE = PAT COPY
USEPAT:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        LEA.L   BLACK(A0),A0                    | POINT TO BLACK PATTERN
        MOVE.L  A0,0x18(SP)                     | REPLACE PATTERN WITH BLACK
        BRA.B   NEWMODE                         | UPDATE MODE AND QUIT

| ----------------------------------------------------------
|
| FORE0
|
FORE0:
        BTST    D2,D1                           | TEST BACKGROUND COLOR BIT
        BNE.B   INVMODE                         | IF BK TRUE, INVERT MODE
        MOVEQ   #12,D3                          | ELSE REPLACE MODE = NOTPAT COPY
        BRA.B   USEPAT                          | AND PATTERN WITH BLACK

| ----------------------------------------------------------
|
| INVMODE
|
INVMODE:
        EORI    #0x4,D3                         | USE INVERSE OF MODE
NEWMODE:
        MOVE    D3,0x1C(SP)                     | CHANGE INPUT MODE
COLOROK:
        MOVEM.L (SP)+,D0-D3/A0                  | RESTORE REGS
        RTS                                     | RETURN TO CALLER

| .FUNC GetPixel,2
| .REF HideCursor,ShowCursor
| ---------------------------------------------------------
|
| FUNCTION GetPixel(h,v: INTEGER): BOOLEAN;
|
| Returns TRUE if the pixel at (h,v) is set to black.
| h and v are in local coords of the current grafport.
|
| CLOBBERS A0,A1,D0,D1,D2
GetPixel:
        JSR     HideCursor(PC)                  | GET RID OF CURSOR
        MOVE.L  (SP)+,D2                        | POP RETURN ADDR
        MOVE.L  (A5),A1                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A1),A1                         | GET THEPORT
        MOVE    (SP)+,D0                        | GET VERT COORD
        SUB     0x8(A1),D0                      | CONVERT VERT TO GLOBAL COORDS
        MOVE    (SP)+,D1                        | GET HORIZ COORD
        SUB     0xA(A1),D1                      | CONVERT HORIZ TO GLOBAL
        MULU    0x6(A1),D0                      | CALC VERT * ROWBYTES
        MOVE.L  0x2(A1),A1                      | GET BASEADDR
        ADD.L   D0,A1                           | ADD VERTICAL OFFSET
        MOVE    D1,D0                           | COPY HORIZ
        NOT     D0                              | INVERT FOR BIT INDEX
        LSR     #3,D1                           | CONVERT DOTS TO BYTES
        BTST    D0,0x0(A1,D1.W)                 | TEST ONE SCREEN BIT
        SNE     (SP)                            | SET BOOLEAN RESULT
        NEG.B   (SP)                            | MAKE $FF --> $01
        MOVE.L  D2,-(SP)                        | PUSH RETURN ADDR
        JMP     ShowCursor(PC)                  | RESTORE CURSOR AND RETURN

| .PROC StuffHex,2
| -------------------------------------------------------
|
| PROCEDURE STUFFHEX(THINGPTR: WORDPTR; S: STR255);
|
| CONVENIENCE ROUTINE TO STUFF HEX INTO ANY VARIABLE.
| BEWARE, NO RANGE-CHECKING.
|
StuffHex:
        MOVE.L  0x4(SP),A0                      | A0:=ADDR OF STRING
        MOVE.L  0x8(SP),A1                      | A1:=THINGPTR
        MOVE.L  (SP),0x8(SP)                    | CLEAN OFF STACK
        ADDQ.W  #0x8,SP                         | POINT TO RETURN ADDR
        MOVE.B  (A0)+,D2                        | GET STRING LENGTH
        ANDI    #0xFE,D2                        | TRUNCATE LENGTH TO EVEN
        BEQ.B   ENDHEX                          | QUIT IF LENGTH = 0
HEXLOOP:
        BSR.B   NEXTHEX                         | GET HEX DIGIT AND CONVERT TO BINARY
        MOVE.B  D0,D1                           | SAVE MOST SIG DIGIT
        BSR.B   NEXTHEX                         | GET HEX DIGIT AND CONVERT TO BINARY
        LSL.B   #4,D1                           | SHIFT MOST SIG INTO PLACE
        ADD.B   D0,D1                           | FILL IN LS NIBBLE
        MOVE.B  D1,(A1)+                        | STUFF BYTE INTO THING
        SUBQ.W  #0x2,D2                         | 2 LESS CHARS TO GO
        BNE.B   HEXLOOP                         | LOOP FOR STRING LENGTH
ENDHEX:
        RTS                                     | RETURN TO PASCAL

| NEXTHEX -- gET HEX DIGIT AND CONVERT TO BINARY.
| ----------------------------------------------------------
|
| NEXTHEX
|
NEXTHEX:
        MOVE.B  (A0)+,D0                        | GET HEX DIGIT FROM STRING
        CMPI.B  #0x39,D0                        | IS IT GTR THAN '9' ?
        BLE.B   SMALL                           | NO, DO IT
        ADDI.B  #0x9,D0                         | ADD CORRECTION
SMALL:
        ANDI.B  #0xF,D0                         | TREAT MOD 16 TO ALLOW LOWER CASE
        RTS                                     | RETURN TO CALLER

| .PROC XorSlab
| .REF MaskTab
| -----------------------------------------------------------
|
| LOCAL PROCEDURE XorSlab(bufAddr: Ptr; left,right: INTEGER);
|
| Enter with:
|
| A0: bufAddr
| D3: left coord
| D4: right coord
|
| Clobbers: A0,D0,D1,D3,D4,D5,D6
|
|
| GET LEFTMASK AND RIGHTMASK
| Called during boot.
XorSlab:
        MOVE.L  A0,D1                           | save bufAddr
        LEA.L   DT_mMaskTab(PC),A0              | point to mask table
        MOVEQ.L #0xF,D0                         | get mask for 4 lo bits
        MOVE    D3,D5                           | COPY LEFT COORD
        AND     D0,D5                           | CALC LEFT MOD 16
        ADD     D5,D5                           | DOUBLE FOR TABLE INDEX
        MOVE    0x0(A0,D5.W),D5                 | GET MASK FROM TABLE
        NOT     D5                              | INVERT FOR LEFTMASK
        MOVE    D4,D6                           | COPY RIGHT COORD
        AND     D0,D6                           | TREAT RIGHT MOD 16
        ADD     D6,D6                           | DOUBLE FOR TABLE INDEX
        MOVE    0x0(A0,D6.W),D6                 | GET RIGHTMASK IN D6
        MOVE.L  D1,A0                           | RESTORE SAVED bufAddr

|
| CALC LEFTWORD, BUFPTR, WORDCOUNT
|
        ASR     #4,D3                           | CONVERT DOTS TO WORDS
        ADD     D3,A0                           | ADD TO bufAddr
        ADD     D3,A0                           | TWICE FOR BYTE OFFSET
        ASR     #4,D4                           | CALC RIGHT DIV 16
        SUB     D3,D4                           | WORDCOUNT:=RIGHTWORD-LEFTWORD
        BGT.B   XORSLAB_NOTIN1                  | BR IF NOT ALL IN ONE

|
| LEFT AND RIGHT ARE ALL IN ONE WORD
|
        AND     D5,D6                           | COMBINE LEFT AND RIGHT MASKS
        EOR     D6,(A0)                         | XOR RIGHTMASK INTO BUFFER
        RTS                                     | AND RETURN

|
| NOT ALL IN ONE WORD. DO LEFT, MIDDLE IF ANY, THEN RIGHT
|
| Called during boot.
XORSLAB_NOTIN1:
        EOR     D5,(A0)+                        | NOTIN1: XOR LEFTMASK INTO BUFFER
        BRA.B   XORSLAB_INVLONG_CONT            | SEE IF ANY FULL WORDS

| ----------------------------------------------------------
|
| XORSLAB_INVLONG
|
| Called during boot.
XORSLAB_INVLONG:
        NOT.L   (A0)+                           | INVLONG: INVERT 2 WHOLE WORDS
XORSLAB_INVLONG_CONT:
        SUBQ.W  #0x2,D4                         | ANY FULL WORDS LEFT ?
        BGT.B   XORSLAB_INVLONG                 | YES, AT LEAST 2
        BLT.B   XORSLAB_ENDWORD                 | NO, FINISH UP LAST WITH MASK
        NOT     (A0)+                           | YES, DO LAST FULL WORD
XORSLAB_ENDWORD:
        EOR     D6,(A0)                         | ENDWORD: XOR RIGHTMASK INTO BUFFER
        RTS                                     | RETURN TO CALLER

|
| LOCAL ROUTINE TO GET NEXT HEX DIGIT AND CONVERT ASCII TO BINARY
|
| .PROC DrawSlab,0
| .DEF SlabMode,FastSlabMode
| .REF MaskTab
| --------------------------------------------------------------
|
| LOCAL PROCEDURE DRAWSLAB
|
| INPUTS:
|
| D0: scratch A0: MASKTAB
| D1: left A1: DSTLEFT, clobbered
| D2: right A2: MASKBUF, clobbered
| D3: A3: MINRECT
| D4: A4: MODECASE
| D5: A5:
| D6: pattern A6:
| D7: A7: stack
|
| CLOBBERS: D0-D3,A1,A2
|
| CLIP LEFT AND RIGHT TO MINRECT:
|
| Called during boot (1,086 times in 30s trace).
DrawSlab:
        CMP     LEFT(A3),D1                     | IS LEFT < MINRECT.LEFT ?
        BGE.B   DRAWSLAB_LEFTOK                 | NO, CONTINUE
        MOVE    LEFT(A3),D1                     | YES, LEFT := MINRECT.LEFT
DRAWSLAB_LEFTOK:
        CMP     RIGHT(A3),D2                    | LEFTOK: IS RIGHT > MINRECT.RIGHT ?
        BLE.B   DRAWSLAB_RIGHTOK                | NO, CONTINUE
        MOVE    RIGHT(A3),D2                    | YES, RIGHT := MINRECT.RIGHT
DRAWSLAB_RIGHTOK:
        CMP     D2,D1                           | RIGHTOK: IS LEFT >= RIGHT ?
        BGE.B   DONESLAB                        | YES, QUIT

|
| SET UP LEFTMASK AND RIGHTMASK: (A0 already points to MaskTab)
|
        MOVEQ.L #0xF,D3                         | get mask for 4 lo bits

        MOVE    D1,D0                           | COPY LEFT
        AND     D3,D1                           | TREAT LEFT MOD 16
        ADD     D1,D1                           | DOUBLE FOR TABLE
        MOVE    0x20(A0,D1.W),D1                | GET LEFTMASK IN D1
        AND     D2,D3                           | GET RIGHT MOD 16
        ADD     D3,D3                           | DOUBLE FOR TABLE
        MOVE    0x0(A0,D3.W),D3                 | GET RIGHTMASK IN D3

|
| CALC WORDCOUNT, DSTPTR, MASKPTR, AND TAKE CASE JUMP
|
        ASR     #4,D2                           | CONVERT RIGHT TO WORDS
        ASR     #4,D0                           | CONVERT LEFT TO WORDS
        SUB     D0,D2                           | CALC WORD COUNT
        ADD     D0,D0                           | DOUBLE FOR BYTES
        ADD     D0,A1                           | OFFSET DSTPTR
        ADD     D0,A2                           | OFFSET MASKPTR
        TST     D2                              | SET Z-FLAG BASED ON WORDCOUNT
        JMP     (A4)                            | TAKE MODECASE TO DRAW SLAB

| ----------------------------------------------------------
|
| DONESLAB
|
| Called during boot.
DONESLAB:
        RTS                                     | RETURN TO CALLER

| ---------------------------------------------------------
|
| INTERFACE TO EACH SCAN LINE ROUTINE:
|
| ENTER WITH Z-FLAG SET IF ALL IN ONE WORD
|
| INPUTS: A1: DSTPTR
| A2: MASKPTR
| D1: LEFTMASK
| D2: WORDCNT
| D3: RIGHTMASK
| D6: PATTERN
|
| CLOBBERS: D0,D1,D2,A1,A2
|

| -------------------------------------------------------
|
| MODE 8 OR 12: PATTERN --> DST
| Called during boot.
DRAWSLAB_END8:
        AND     D3,D1                           | END8: COMBINE RIGHT AND LEFT MASK
NEXT8:
        MOVE    D6,D0                           | GET PATTERN DATA
        AND     (A2)+,D1                        | MERGE MASK AND CLIPRGN MASK
        AND     D1,D0                           | MASK PATTERN DATA
        NOT     D1                              | MAKE NOTMASK
        AND     (A1),D1                         | AND NOTMASK WITH OLD DST
        OR      D0,D1                           | FILL HOLE WITH PATTERN
        MOVE    D1,(A1)+                        | UPDATE DST
        MOVEQ   #-1,D1                          | FLUSH MASK
        SUBQ.W  #0x1,D2                         | DEC WORD COUNT
NEXT8_CONT:
        BGT.B   NEXT8                           | LOOP FOR ALL WORDS IN ROW
        BEQ.B   DRAWSLAB_END8                   | DO LAST WORD WITH MASK
        RTS                                     | RETURN TO CALLER


| -------------------------------------------------------
|
| MODE 9 OR 13: PATTERN OR DST --> DST
|
END9:
        AND     D3,D1                           | COMBINE RIGHT AND LEFT MASK
NEXT9:
        AND     D6,D1                           | GET PATTERN DATA
        AND     (A2)+,D1                        | MERGE MASK AND CLIPRGN MASK
        OR      D1,(A1)+                        | OR RESULT INTO DST
        MOVEQ   #-1,D1                          | FLUSH MASK
        SUBQ.W  #0x1,D2                         | DEC WORD COUNT
NEXT9_CONT:
        BGT.B   NEXT9                           | LOOP FOR ALL WORDS IN ROW
        BEQ.B   END9                            | DO LAST WORD WITH MASK
        RTS                                     | RETURN TO CALLER


| -------------------------------------------------------
|
| MODE 10 OR 14: PATTERN XOR DST --> DST
|
END10:
        AND     D3,D1                           | COMBINE RIGHT AND LEFT MASK
NEXT10:
        AND     D6,D1                           | GET PATTERN DATA
        AND     (A2)+,D1                        | MERGE MASK AND CLIPRGN MASK
        EOR     D1,(A1)+                        | XOR RESULT INTO DST
        MOVEQ   #-1,D1                          | FLUSH MASK
        SUBQ.W  #0x1,D2                         | DEC WORD COUNT
NEXT10_CONT:
        BGT.B   NEXT10                          | LOOP FOR ALL WORDS IN ROW
        BEQ.B   END10                           | DO LAST WORD WITH MASK
        RTS                                     | RETURN TO CALLER


| -------------------------------------------------------
|
| MODE 11 OR 15: PATTERN BIC DST --> DST
|
END11:
        AND     D3,D1                           | COMBINE RIGHT AND LEFT MASK
NEXT11:
        AND     D6,D1                           | GET PATTERN DATA
        AND     (A2)+,D1                        | MERGE MASK AND CLIPRGN MASK
        NOT     D1                              | INVERT FOR BIC
        AND     D1,(A1)+                        | BIC RESULT INTO DST
        MOVEQ   #-1,D1                          | FLUSH MASK
        SUBQ.W  #0x1,D2                         | DEC WORD COUNT
NEXT11_CONT:
        BGT.B   NEXT11                          | LOOP FOR ALL WORDS IN ROW
        BEQ.B   END11                           | DO LAST WORD WITH MASK
        RTS                                     | RETURN TO CALLER

| --------------------------------------------
|
| PROCEDURE SlabMode
|
| INPUT: D2: MODE, CLOBBERED
| OUTPUT: A4: MODECASE
|
| Called during boot.
SlabMode:
        ANDI    #0x3,D2                         | GET LO 2 BITS OF MODE

| RTS
        LEA.L   SLABMODE_MODE_TBL(PC),A4        | POINT TO MODE TABLE
        MOVE.B  0x0(A4,D2.W),D2                 | GET OFFSET FROM MODETAB
        SUB     D2,A4                           | GET CASE JUMP ADDRESS
        RTS                                     | RETURN TO CALLER

| ----------------------------------------------------------
|
| SLABMODE_MODE_TBL
|
SLABMODE_MODE_TBL:
  .byte 0x4E,0x3C,0x2A,0x16                     | SLAB MODE OFFSETS: 0-3


| .BYTE MODETAB-MASK9
| .BYTE MODETAB-MASK10
| .BYTE MODETAB-MASK11

| ---------------------------------------------------------------
|
| FAST LOOPS, OPTIMIZED FOR BLACK PATTERN AND RECTANGLE CLIPPED
|
| FAST BLACK SLAB:
|
| Called during boot.
SLABMODE_CONT:
        BEQ.B   MERGE8                          | BR IF ALL IN ONE WORD
        OR      D1,(A1)+                        | OR LEFTMASK INTO DST
        SUBQ.W  #0x2,D2                         | ADJUST WORDCOUNT FOR DBF
        BLT.B   LAST8                           | BR IF NO UNMASKED WORDS
        MOVEQ   #-1,D1                          | GET SOME BLACK
LOOP8:
        MOVE    D1,(A1)+                        | WRITE A WORD OF BLACK
        DBF     D2,LOOP8                        | LOOP ALL UNMASKED WORDS
MERGE8:
        AND     D1,D3                           | COMBINE LEFTMASK AND RIGHTMASK
LAST8:
        OR      D3,(A1)+                        | OR RIGHTMASK INTO DST
        RTS                                     | AND RETURN

| ----------------------------------------------------------
|
| LAST8_CONT
|
| Called during boot.
LAST8_CONT:

|
| FAST XOR SLAB:
|
        BEQ.B   MERGE10                         | BR IF ALL IN ONE WORD
        EOR     D1,(A1)+                        | XOR LEFTMASK INTO DST
        SUBQ.W  #0x2,D2                         | ADJUST WORDCOUNT FOR DBF
        BLT.B   LAST10                          | BR IF NO UNMASKED WORDS
LOOP10:
        NOT     (A1)+                           | INVERT A WORD OF DST
        DBF     D2,LOOP10                       | LOOP ALL UNMASKED WORDS
        BRA.B   LAST10                          | THEN FINISH UP LAST WITH MASK

| ----------------------------------------------------------
|
| MERGE10
|
MERGE10:
        AND     D1,D3                           | COMBINE LEFTMASK AND RIGHTMASK
LAST10:
        EOR     D3,(A1)+                        | XOR RIGHTMASK INTO DST
        RTS                                     | AND RETURN

| ----------------------------------------------------------
|
| LAST10_CONT
|
| Called during boot.
LAST10_CONT:

|
| FAST WHITE SLAB:
|
        BEQ.B   MERGE11                         | BR IF ALL IN ONE WORD
        NOT     D1                              | FORM NOT LEFTMASK
        AND     D1,(A1)+                        | AND NOT LEFTMASK INTO DST
        SUBQ.W  #0x2,D2                         | ADJUST WORDCOUNT FOR DBF
        BLT.B   LAST11                          | BR IF NO UNMASKED WORDS
LOOP11:
        CLR     (A1)+                           | CLEAR A WORD OF DST
        DBF     D2,LOOP11                       | LOOP ALL UNMASKED WORDS
        BRA.B   LAST11                          | THEN FINISH UP LAST WITH MASK

| ----------------------------------------------------------
|
| MERGE11
|
MERGE11:
        AND     D1,D3                           | COMBINE LEFTMASK AND RIGHTMASK
LAST11:
        NOT     D3                              | FORM NOT RIGHTMASK
        AND     D3,(A1)+                        | AND NOT RIGHTMASK INTO DST
        RTS                                     | AND RETURN

| --------------------------------------------------------------------
|
| PROCEDURE FastSlabMode, Call when rect clipped and pattern black.
|
| INPUT: D2: MODE, CLOBBERED mode 0=black, 1=xor, 2=white
| OUTPUT: A4: MODECASE
|
| Called during boot.
FastSlabMode:
        ANDI    #0x3,D2                         | GET LO 2 BITS OF MODE
        LEA.L   FASTSLABMODE_MODE_TBL(PC),A4    | POINT TO MODE TABLE
        MOVE.B  0x0(A4,D2.W),D2                 | GET OFFSET FROM FASTTAB
        SUB     D2,A4                           | GET CASE JUMP ADDRESS
        RTS                                     | RETURN TO CALLER

| ----------------------------------------------------------
|
| FASTSLABMODE_MODE_TBL
|
FASTSLABMODE_MODE_TBL:
  .byte 0x56,0x40,0x2A,0x00                     | FAST SLAB MODE OFFSETS: 0-3

| FASTSLABMODE_CONT -- aLLOCATE PTBUF.
| Called by: OpenPoly, NewRgn, OpenRgn, INSETRGN_NOTRECT, JDONE_NO_2 (and 1 more)
FASTSLABMODE_CONT:
        MOVEQ.L #0x0,D0                         | CLEAR UPPER WORD OF SIZE
        MOVE.L  (SP)+,A1                        | POP RETURN ADDRESS
        MOVE    (SP)+,D0                        | GET SIZE PARAMETER
        _NewHandle                              | ALLOCATE HANDLE
        BNE.B   FASTSLABMODE_ERR                | BRANCH IF ALLOCATION FAILED
        MOVE.L  A0,(SP)                         | RETURN HANDLE ON STACK
        JMP     (A1)                            | RETURN TO CALLER

| ----------------------------------------------------------
|
| FASTSLABMODE_ERR
|
FASTSLABMODE_ERR:
        MOVEQ.L #0x19,D0                        | LOAD OUT OF MEMORY ERROR CODE
        _SysError                               | TRIGGER SYSTEM ERROR
        _Debugger                               | DROP INTO DEBUGGER
| SetHSize -- mAKE THE BUFFER BIGGER.
| Called by: DOLINE_NO, DVPOS_OK, PutRect, PUTPT, EMPTY (and 6 more)
SetHSize:
        MOVEQ.L #0x0,D0                         | CLEAR UPPER WORD OF SIZE
        MOVE.L  (SP)+,A1                        | POP RETURN ADDRESS
        MOVE    (SP)+,D0                        | GET NEW SIZE PARAMETER
        MOVE.L  (SP)+,A0                        | GET HANDLE PARAMETER
        _SetHandleSize                          | SET HANDLE SIZE
        BNE.B   FASTSLABMODE_ERR                | BRANCH IF ERROR
        JMP     (A1)                            | RETURN TO CALLER
