| QuickDraw Utility (ROM $53B4-$5803), from the 1983 Util.a: the bit
| routines BitAnd, BitXor, BitNot, BitOr, BitShift, BitTst, BitSet and
| BitClr, Random, ForeColor/BackColor/ColorBit, BitMask/LeftMask with
| MASKTAB, PatExpand, ColorMap, GetPixel, StuffHex, DrawSlab and
| SlabMode with its slab-drawing loops (SLAB_*). XorSlab is not here: the
| 64K ROM links it after StretchBits (Stretch.s).

| -----------------------------------------------------------
| Function BitAnd(long1,long2: LongInt): LongInt;
BitAnd:                                         | jump via A0
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,D0                        | GET ONE LONG
        AND.L   (SP)+,D0                        | AND IT WITH THE OTHER
        MOVE.L  D0,(SP)                         | STORE RESULT
        JMP     (A0)                            | RTS

| -----------------------------------------------------------
| Function BitXor(long1,long2: LongInt): LongInt;
BitXor:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,D0                        | GET ONE LONG
        MOVE.L  (SP)+,D1                        | GET THE SECOND
        EOR.L   D1,D0                           | XOR BOTH
        MOVE.L  D0,(SP)                         | STORE RESULT
        JMP     (A0)                            | RTS

| -------------------------------------------------------------
| --> UTIL.TEXT
| SMALL UTILITY ROUTINES USED BY QuickDraw.
| .FUNC BitNot,1
| -----------------------------------------------------------
| Function BitNot(long: LongInt): LongInt;
BitNot:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        NOT.L   (SP)                            | INVERT LONG
        MOVE.L  (SP)+,(SP)                      | STORE INTO RESULT
        JMP     (A0)                            | AND RETURN

| -----------------------------------------------------------
| Function BitOr(long1,long2: LongInt): LongInt;
BitOr:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,D0                        | GET ONE LONG
        OR.L    (SP)+,D0                        | OR IT WITH THE OTHER
        MOVE.L  D0,(SP)                         | STORE RESULT
        JMP     (A0)                            | RTS

| -----------------------------------------------------------
| Function BitShift(long: LongInt; count: INTEGER): LongInt;
| positive count --> shift left.
| negative count --> shift right.
BitShift:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE    (SP)+,D1                        | GET COUNT
        BPL.B   SHLEFT                          | SHIFT LEFT IF POSITIVE
        NEG     D1                              | MAKE COUNT POSITIVE
        MOVE.L  (SP)+,D0                        | GET LONG
        LSR.L   D1,D0                           | SHIFT IT RIGHT
        BRA.B   BITSHIFT_DONE                   | AND STORE RESULT
SHLEFT:
        MOVE.L  (SP)+,D0                        | GET LONG
        LSL.L   D1,D0                           | SHIFT IT LEFT
BITSHIFT_DONE:
        MOVE.L  D0,(SP)                         | STORE RESULT
        JMP     (A0)                            | RTS
| ----------------------------------------------------------
|
| _BitTst ($A85D): test one bit
| Pascal: FUNCTION BitTst(bytePtr: Ptr; bitNum: LongInt): BOOLEAN;
| Bits are numbered from the high-order bit of bytePtr^: byte offset =
| bitNum DIV 8 (ASR.L #3), bit within the byte = NOT bitNum (mod 8 in BTST),
| so bitNum 0 is bit 7 ($80) of the first byte.
| The 1983 Util.a shares this prologue via BSR SHARE; the 1984 ROM inlines
| it into BitTst, BitSet and BitClr.
|
BitTst:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,D1                        | D1 = bit number
        MOVE    D1,D0                           | D0 = copy of bit num
        ASR.L   #0x3,D1                         | D1 = byte offset (bits / 8)
        NOT     D0                              | reverse bit sense (BTST counts from LSB)
        MOVE.L  (SP)+,A1                        | GET PTR
        BTST    D0,0(A1,D1.L)                   | TEST THE BIT
        SNE     (SP)                            | SET OR CLEAR RESULT
        NEG.B   (SP)                            | CONVERT -1 TO 1 (TRUE)
        JMP     (A0)                            | RTS
| ----------------------------------------------------------
|
| _BitSet ($A85E): set one bit
| Pascal: PROCEDURE BitSet(bytePtr: Ptr; bitNum: LongInt);
| Same bit numbering as BitTst (bitNum 0 = high-order bit of bytePtr^).
|
BitSet:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,D1                        | D1 = bit number
        MOVE    D1,D0                           | D0 = copy of bit num
        ASR.L   #0x3,D1                         | D1 = byte offset (bits / 8)
        NOT     D0                              | reverse bit sense
        MOVE.L  (SP)+,A1                        | GET PTR
        BSET    D0,0(A1,D1.L)                   | SET THE BIT
        JMP     (A0)                            | RTS
| ----------------------------------------------------------
|
| _BitClr ($A85F): clear one bit
| Pascal: PROCEDURE BitClr(bytePtr: Ptr; bitNum: LongInt);
| Same bit numbering as BitTst (bitNum 0 = high-order bit of bytePtr^).
|
BitClr:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,D1                        | GET BITNUM
        MOVE    D1,D0                           | COPY IT
        ASR.L   #0x3,D1                         | D1 = byte offset (bits / 8)
        NOT     D0                              | REVERSE BIT SENSE
        MOVE.L  (SP)+,A1                        | A1 = byte pointer
        BCLR    D0,0(A1,D1.L)                   | CLEAR THE BIT
        JMP     (A0)                            | RTS
| ----------------------------------------------------------
|
| _Random ($A861): return a pseudo-random integer
| Pascal: FUNCTION Random: INTEGER;
| Exit:  function result (4(SP)) = low word of the new randSeed, with -32768
|        replaced by 0; randSeed updated. Clobbers D0-D2/A0.
| From the 1983 Util.a: randSeed := (randSeed * 16807) MOD (2^31-1), computed
| with 16x16-bit MULUs (Schrage, ACM Trans. Math. Software 5(2), 1979).
| randSeed is the QuickDraw global at -$7E from the (A5) globals pointer.
|
Random:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE    #0x41A7,D0                      | D0 = a = 16807 (7^5)
        MULU    -0x7C(A0),D0                    | xalo := a * LoWord(randSeed)
        MOVE.L  D0,D1                           | COPY xalo
        CLR     D1                              | zero low word of D1
        SWAP    D1                              | GET HiWord(xalo) as a long
        MOVE    #0x41A7,D2                      | D2 = a = 16807 again
        MULU    -0x7E(A0),D2                    | a * HiWord(randSeed)
        ADD.L   D1,D2                           | ADD LEFTLO = FHI
        MOVE.L  D2,D1                           | COPY FHI
        ADD.L   D1,D1                           | CALC 2 TIMES FHI
        CLR     D1                              | zero low word of D1
        SWAP    D1                              | CALC FHI SHIFTED RIGHT 15 FOR K
        ANDI.L  #0xFFFF,D0                      | GET LO WORD XALO
        SUBI.L  #0x7FFFFFFF,D0                  | SUBTRACT P = 2^31-1
        ANDI.L  #0x7FFF,D2                      | BitAnd(fhi,$00007FFF)
        SWAP    D2                              | TIMES 64K
        ADD.L   D1,D2                           | PLUS K
        ADD.L   D2,D0                           | CALC TOTAL
        BPL.B   RANDOM_UPDATE                   | seed >= 0 -> done
        ADDI.L  #0x7FFFFFFF,D0                  | seed < 0: ADD P BACK
RANDOM_UPDATE:
        MOVE.L  D0,-0x7E(A0)                    | UPDATE SEED
        CMPI    #-0x8000,D0                     | IS NUMBER -32768 ?
        BNE.B   RANDOM_UPDATE_NO                | NO, CONTINUE
        CLR     D0                              | YES, RETURN ZERO INSTEAD
RANDOM_UPDATE_NO:
        MOVE    D0,4(SP)                        | return low word as Pascal result
        RTS                                     | AND RETURN
| ----------------------------------------------------------
|
| _ForeColor ($A862): set the current port's foreground color
| Pascal: PROCEDURE ForeColor(color: LongInt);
| Stores color into thePort^.fgColor ($50) through PortLong (L_mPortLong).
|
ForeColor:
        MOVEQ.L #0x50,D0                        | ForeColor: D0 = fgColor offset ($50)
        JMP     L_mPortLong(PC)                 | install long into thePort
| ----------------------------------------------------------
|
| _BackColor ($A863): set the current port's background color
| Pascal: PROCEDURE BackColor(color: LongInt);
| Stores color into thePort^.bkColor ($54) through PortLong (L_mPortLong).
|
BackColor:
        MOVEQ.L #0x54,D0                        | BackColor: D0 = bkColor offset ($54)
        JMP     L_mPortLong(PC)                 | install long into thePort
| ----------------------------------------------------------
|
| _ColorBit ($A864): select the color plane for subsequent drawing
| Pascal: PROCEDURE ColorBit(whichBit: INTEGER);
| Stores whichBit into thePort^.colrBit ($58) through PortWord (L_mPortWord).
|
ColorBit:
        MOVEQ.L #0x58,D0                        | ColorBit: D0 = colrBit offset ($58)
        JMP     L_mPortWord(PC)                 | install word into thePort
| ----------------------------------------------------------
| .PROC GetMaskTab,0
| .DEF LeftMask,RightMask,BitMask,MaskTab
| ASSEMBLY LANGUAGE CALLABLE PROCEDURES LEFTMASK, RIGHTMASK, AND BITMASK:
| ENTER WITH COORDINATE IN D0, RETURNS WITH 16 BIT MASK IN D0
| NO OTHER REGISTERS ALTERED.
| Called by: DRAWSLAB_BODY, CLRLOOP_CONT_9, DRAWLINE_ABLOOP_NO, GETSRC_CONT, SEEKRGN_NEXTHOR_CONT_2 (and 1 more)
BitMask:
        ANDI    #0xF,D0                         | treat coordinate mod 16
        ADD     D0,D0                           | DOUBLE FOR TABLE
        MOVE.W  MASKTAB(PC,D0.W),D0             | fetch right-mask word
        NOT     D0                              | invert to get actual LEFT mask
        RTS                                     | return to caller (@ $549E)
| ----------------------------------------------------------
| Left Mask
| Called during boot.
LeftMask:
        ANDI    #0xF,D0                         | TREAT MOD 16
        ADD     D0,D0                           | DOUBLE FOR TABLE
        MOVE.W  MASKTAB(PC,D0.W),D0             | GET RIGHT MASK (labeled LEFT in ROM)
        RTS                                     | return from LeftMask
LEFTMASK_CONT:
        ANDI    #0xF,D0                         | treat coordinate mod 16
        ADD     D0,D0                           | DOUBLE FOR TABLE
        MOVE.W  (MASKTAB+0x20)(PC,D0.W),D0      | fetch single-bit mask word
        RTS                                     | return single-bit mask in D0
| --- MASKTAB @ $54B8 (from historic Util.a) ---
| MASKTAB+$00: RIGHT MASKS -- $0000, $8000, $C000, ..., $FFFE (16 words)
| fills in bits from the left, leaving the right unchanged
MASKTAB:
        .byte   0x00, 0x00, 0x80, 0x00, 0xC0, 0x00, 0xE0, 0x00
        .byte   0xF0, 0x00, 0xF8, 0x00, 0xFC, 0x00, 0xFE, 0x00
        .byte   0xFF, 0x00, 0xFF, 0x80, 0xFF, 0xC0, 0xFF, 0xE0
        .byte   0xFF, 0xF0, 0xFF, 0xF8, 0xFF, 0xFC, 0xFF, 0xFE
| MASKTAB+$20: BIT MASKS -- $8000, $4000, $2000, ..., $0001 (16 words)
| single-bit masks shifted right from MSB
        .byte   0x80, 0x00, 0x40, 0x00, 0x20, 0x00, 0x10, 0x00
        .byte   0x08, 0x00, 0x04, 0x00, 0x02, 0x00, 0x01, 0x00
        .byte   0x00, 0x80, 0x00, 0x40, 0x00, 0x20, 0x00, 0x10
        .byte   0x00, 0x08, 0x00, 0x04, 0x00, 0x02, 0x00, 0x01
| ----------------------------------------------------------
| PatExpand @ $54F8 -- dispatch on patMode (mode 2 = double, mode -2 = thin, else NORMAL)
| Called during boot.
PatExpand:
        LINK    A6,#-0x10                       | local frame: 16 bytes
        MOVE.L  A4,-(SP)                        | save A4
        MOVEA.L (A5),A4                         | A4 := QuickDraw globals
        MOVEQ.L #0x7,D0                         | mask for mode bits 0-2
        AND.W   -0xA8(A4),D0                    | D0 := patMode & 7
        BEQ.B   PATEXPAND_SKIP                  | mode 0: skip expand
        MOVE.L  (A0),-0x10(A6)                  | copy pattern low long
        MOVE.L  4(A0),-0xC(A6)                  | copy pattern high long
        MOVE.L  (A0),-0x8(A6)                   | duplicate pattern low
        MOVE.L  4(A0),-0x4(A6)                  | duplicate pattern high
        LEA.L     -0x10(A6),A0                  | A0 := local pattern buf
        ADDA.W  D0,A0                           | skew by patMode & 7
PATEXPAND_SKIP:
        ADD     -0xA6(A4),D2                    | ADJUST FOR PATALIGN HORIZ
        ANDI    #0x7,D2                         | treat shift count mod 8
        MOVEQ.L #0x7,D1                         | loop count: 8 input bytes
        MOVE.L  (A4),A4                         | A4 = thePort
        MOVE    0x5A(A4),D0                     | D0 = patStretch
        CMPI    #0x2,D0                         | patStretch == 2?
        BEQ.B   NORMAL_CONT                     | YES, DOUBLE
        CMPI    #-0x2,D0                        | patStretch == -2?
        BEQ.B   DLOOP_CONT                      | YES, STRETCH THIN
| ANY OTHER, USE NORMAL

| ---------------------------------------------------------
| NORMAL PATTERN. SIMPLY REPLICATE THE 8 BY 8 PATTERN.
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
NORMAL_CONT:                                    | mode 2 entry: clear D0, fall into DLOOP
        CLR.W   D0                              | clear D0 (high nibble of first write)
DLOOP:                                          | doubled-pattern loop @ $555A
        MOVE.B  (A0)+,D0                        | GET A BYTE OF PATTERN
        EOR.B   D7,D0                           | INVERT IT IF MODE BIT 2
        ROL.B   D2,D0                           | ALIGN TO LOCAL COORDS
        MOVE.B  D0,-(SP)                        | STASH FOR A WHILE
        LSR.B   #0x4,D0                         | GET HI NIBBLE
        MOVE.B  STRETCH(PC,D0.W),(A1)+          | PUT ONE BYTE
        MOVEQ.L #0xF,D0                         | MASK FOR LO NIBBLE
        AND.B   (SP)+,D0                        | GET THE LO NIBBLE
        MOVE.B  STRETCH(PC,D0.W),(A1)+          | PUT ANOTHER TO MAKE A WORD
        MOVE    -2(A1),(A1)+                    | STRETCH WORD OUT TO LONG
        MOVE.L  -4(A1),(A1)+                    | STRETCH LONG TO TWO LONGS
        DBRA    D1,DLOOP                        | LOOP ALL 8 INPUT BYTES
        BRA.B   PATEXPAND_DONE                  | DONE WITH DOUBLED PATTERN
DLOOP_CONT:                                     | mode -2 entry: clear D0, fall into THINLP
        CLR.W   D0                              | clear D0 (high nibble of first write)
THINLP:                                         | thin-pattern loop @ $5580
        MOVE.B  (A0)+,D0                        | GET A BYTE OF PATTERN
        EOR.B   D7,D0                           | INVERT IT IF MODE BIT 2
        ROL.B   D2,D0                           | ALIGN TO LOCAL COORDS
        MOVE.B  D0,-(SP)                        | STASH FOR A WHILE
        LSR.B   #0x4,D0                         | GET HI NIBBLE
        MOVE.B  THINSTR(PC,D0.W),(A1)+          | PUT ONE BYTE
        MOVEQ.L #0xF,D0                         | MASK FOR LO NIBBLE
        AND.B   (SP)+,D0                        | GET THE LO NIBBLE
        MOVE.B  THINSTR(PC,D0.W),(A1)+          | PUT ANOTHER TO MAKE A WORD
        MOVE    -2(A1),(A1)+                    | STRETCH WORD OUT TO LONG
        CLR.L   (A1)+                           | STRETCH LONG TO TWO LONGS
        DBRA    D1,THINLP                       | LOOP ALL 8 INPUT BYTES
PATEXPAND_DONE:
        MOVE.L  (SP)+,A4                        | DONE: RESTORE REG
        UNLK    A6                              | RELEASE STACK FRAME
        RTS                                     | return from PATEXPAND_DONE
| --- STRETCH (bit-doubling) table -- 16 bytes, map nibble -> byte where each bit is doubled ---
| used by DLOOP to expand doubled patterns

| ----------------------------------------------------------
| STRETCH
| Called during boot.
STRETCH:
        .byte   0x00, 0x03, 0x0C, 0x0F, 0x30, 0x33, 0x3C, 0x3F
        .byte   0xC0, 0xC3, 0xCC, 0xCF, 0xF0, 0xF3, 0xFC, 0xFF
| --- THINSTR (thin-doubling) table -- 16 bytes, map nibble -> byte for thin patterns ---
| used by THINLP for thin doubled patterns
THINSTR:
        .byte   0x00, 0x01, 0x04, 0x05, 0x10, 0x11, 0x14, 0x15
        .byte   0x40, 0x41, 0x44, 0x45, 0x50, 0x51, 0x54, 0x55
| ColorMap - QuickDraw ColorMap helper: pen color lookup via QD globals
ColorMap:
        MOVEM.L D0-D3/A0,-(SP)                  | RESTORE REGS
        MOVE.L  (A5),A0                         | A0 = QuickDraw globals
        MOVE.L  (A0),A0                         | A0 = thePort
        MOVE    0x58(A0),D2                     | D2 = colrBit (which color plane)
        MOVE    28(SP),D3                       | POP RETURN ADDR
        MOVEQ.L #0x3,D0                         | mask for low 2 mode bits
        AND     D3,D0                           | GET 2 BITS OF MODE
        BEQ.B   COLORMAP_COPY                   | BR IF COPY MODE
        CMPI    #0x2,D0                         | mode == OR?
        BEQ.B   COLOROK                         | jump via A1
        BGT.B   BICMODE                         | BRANCH IF BIC
        MOVE.L  0x50(A0),D1                     | POINT TO QUICKDRAW GLOBALS
COLORMAP_SHARE:
        BTST    D2,D1                           | SHARE: TEST FOREGROUND COLOR BIT
        BNE.B   COLOROK                         | NO CHANGE IF FG TRUE
        EORI    #0x2,D3                         | INVERT MODE BIT 2
        BRA.B   NEWMODE                         | UPDATE MODE AND QUIT
BICMODE:
        MOVE.L  0x54(A0),D1                     | GET BACKGROUND COLOR
        NOT.L   D1                              | INVERT IT
        BRA.B   COLORMAP_SHARE                  | AND SHARE CODE
COLORMAP_COPY:
        MOVE.L  0x50(A0),D0                     | COPY: GET FOREGROUND COLOR
        MOVE.L  0x54(A0),D1                     | GET BACKGROUND COLOR
        BTST    D2,D0                           | TEST FOREGROUND COLOR BIT
        BEQ.B   FORE0                           | BRANCH IF IT'S ZERO
        BTST    D2,D1                           | test bit D2 of D1
        BEQ.B   COLOROK                         | NO CHANGE IF BKGND FALSE
        MOVE    #0x8,D3                         | D3 = mode 8 (srcCopy with patBlack)
USEPAT:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        LEA.L     -16(A0),A0                    | POINT TO BLACK PATTERN
        MOVE.L  A0,24(SP)                       | REPLACE PATTERN WITH BLACK
        BRA.B   NEWMODE                         | UPDATE MODE AND QUIT
FORE0:
        BTST     D2,D1                          | TEST BACKGROUND COLOR BIT
        BNE.B   INVMODE                         | IF BK TRUE, INVERT MODE
        MOVE    #0xC,D3                         | D3 = mode 12 (notSrcCopy: invert pat)
        BRA.B   USEPAT                          | AND PATTERN WITH BLACK
INVMODE:
        EORI    #0x4,D3                         | XOR immediate: #0x4,D3
NEWMODE:
        MOVE    D3,28(SP)                       | jump via A0
COLOROK:
        MOVEM.L (SP)+,D0-D3/A0                  | RESTORE REGS
        RTS                                     | AND RETURN

| -------------------------------------------------------
| PROCEDURE PortWord(word: INTEGER);   (L_mPortWord)
| PROCEDURE PortLong(long: LongInt);   (L_mPortLong)
| INSTALL A WORD / LONG INTO THE CURRENT GRAFPORT. ENTER WITH THE FIELD
| OFFSET IN D0; the value is popped off the stack. Tail-jumped to by
| ForeColor/BackColor (PortLong) and ColorBit, GrafDevice, TextFont,
| TextMode, TextSize, PenMode (PortWord).
| Called during boot.
L_mPortWord:
        MOVE.L  (SP)+,A1                        | POP RETURN ADDR
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | POINT TO THEPORT
        MOVE    (SP)+,0x0(A0,D0.W)              | INSTALL WORD INTO THEPORT
        JMP     (A1)                            | AND RETURN
L_mPortLong:
        MOVE.L  (SP)+,A1                        | POP RETURN ADDR
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | POINT TO THEPORT
        MOVE.L  (SP)+,0x0(A0,D0.W)              | INSTALL LONG INTO THEPORT
        JMP     (A1)                            | AND RETURN

| ----------------------------------------------------------
| FUNCTION GetPixel(h, v: INTEGER): BOOLEAN;
| Returns TRUE if pixel at (h,v) is black.
GetPixel:
        JSR     HideCursor(PC)                  | GET RID OF CURSOR
        MOVE.L  (SP)+,D2                        | POP RETURN ADDR
        MOVE.L  (A5),A1                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A1),A1                         | GET THEPORT
        MOVE    (SP)+,D0                        | GET VERT COORD
        SUB     8(A1),D0                        | CONVERT VERT TO GLOBAL COORDS
        MOVE    (SP)+,D1                        | GET HORIZ COORD
        SUB     10(A1),D1                       | CONVERT HORIZ TO GLOBAL
        MULU    6(A1),D0                        | D0 = D0 *u 6(A1)
        MOVE.L  2(A1),A1                        | GET BASEADDR
        ADDA.L  D0,A1                           | ADD VERTICAL OFFSET
        MOVE    D1,D0                           | COPY HORIZ
        NOT     D0                              | INVERT FOR BIT INDEX
        LSR     #0x3,D1                         | CONVERT DOTS TO BYTES
        BTST    D0,0(A1,D1.W)                   | TEST ONE SCREEN BIT
        SNE     (SP)                            | SET BOOLEAN RESULT
        NEG.B   (SP)                            | MAKE $FF --> $01
        MOVE.L  D2,-(SP)                        | PUSH RETURN ADDR
        JMP     ShowCursor(PC)                  | RESTORE CURSOR AND RETURN
        MOVE.L  4(SP),A0                        | A0 = arg pointer (skip return addr)
        MOVE.L  (SP)+,(SP)                      | pop return addr, overwrite arg slot
        JMP     (A0)                            | RTS
| ----------------------------------------------------------
| PROCEDURE StuffHex(thingPtr: Ptr; hexStr: Str255);
| Convert a hex string to bytes and stuff into thingPtr. No
| range-checking.
StuffHex:
        MOVE.L  4(SP),A0                        | A0:=ADDR OF STRING
        MOVE.L  8(SP),A1                        | A1:=THINGPTR
        MOVE.L  (SP),8(SP)                      | CLEAN OFF STACK
        ADDQ.W  #0x8,SP                         | POINT TO RETURN ADDR
        MOVE.B  (A0)+,D2                        | GET STRING LENGTH
        ANDI    #0xFE,D2                        | TRUNCATE LENGTH TO EVEN
        BEQ.B   ENDHEX                          | QUIT IF LENGTH = 0
HEXLOOP:
        BSR.B   NEXTHEX                         | GET HEX DIGIT AND CONVERT TO BINARY
        MOVE.B  D0,D1                           | SAVE MOST SIG DIGIT
        BSR.B   NEXTHEX                         | GET HEX DIGIT AND CONVERT TO BINARY
        LSL.B   #0x4,D1                         | SHIFT MOST SIG INTO PLACE
        ADD.B   D0,D1                           | FILL IN LS NIBBLE
        MOVE.B  D1,(A1)+                        | STUFF BYTE INTO THING
        SUBQ.W  #0x2,D2                         | 2 LESS CHARS TO GO
        BNE.B   HEXLOOP                         | LOOP FOR STRING LENGTH
ENDHEX:
        RTS                                     | return to caller (@ $56AC)
NEXTHEX:
        MOVE.B  (A0)+,D0                        | GET HEX DIGIT FROM STRING
        CMPI.B  #0x39,D0                        | IS IT GTR THAN '9' ?
        BLE.B   SMALL                           | NO, DO IT
        ADDI.B  #0x9,D0                         | yes, add 9 ('A'-'9'+1) for A-F
SMALL:
        ANDI.B  #0xF,D0                         | treat mod 16 (handles upper/lower)
        RTS                                     | AND RETURN
DrawSlab:
        CMP     D2,D1                           | left >= right? (empty slab)
        BGE.B   DONESLAB                        | yes -> nothing to draw
        CMP     6(A3),D1                        | left >= MINRECT.RIGHT?
        BGE.B   DONESLAB                        | yes -> entirely off-rect
        CMP     2(A3),D1                        | IS LEFT < MINRECT.LEFT ?
        BGE.B   DRAWSLAB_RIGHTCLIP              | NO, CONTINUE
        MOVE    2(A3),D1                        | YES, LEFT := MINRECT.LEFT
DRAWSLAB_RIGHTCLIP:
        CMP     2(A3),D2                        | right <= MINRECT.LEFT?
        BLE.B   DONESLAB                        | yes -> entirely off-rect
        CMP     6(A3),D2                        | IS RIGHT > MINRECT.RIGHT ?
        BLE.B   DRAWSLAB_BODY                   | NO, CONTINUE
        MOVE    6(A3),D2                        | YES, RIGHT := MINRECT.RIGHT
DRAWSLAB_BODY:
        MOVE    D2,D0                           | D0 = right coord
        JSR     LeftMask(PC)                    | D0 = right-mask
        MOVE    D0,D3                           | D3 = right-mask
        MOVE    D1,D0                           | COPY LEFT
        JSR     BitMask(PC)                     | D0 = left-mask (inverted right-mask)
        EXG     D0,D1                           | D1 = left-mask, D0 = left coord
        ASR     #0x3,D0                         | left coord -> bytes
        ANDI    #-0x2,D0                        | align to word boundary
        ADDA.W  D0,A1                           | OFFSET DSTPTR
        ADDA.W  D0,A2                           | OFFSET MASKPTR
        ASR     #0x3,D2                         | right coord -> bytes
        ANDI    #-0x2,D2                        | align to word boundary
        SUB     D0,D2                           | D2 = byte span
        ASR     #0x1,D2                         | D2 = word count
        JMP     (A0)                            | RTS
DONESLAB:
        RTS                                     | return from DrawSlab
SlabMode:
        ANDI    #0x3,D2                         | get low 2 bits of mode
        ADD     D2,D2                           | double for word offset
        LEA     SLABMODE_TBL(PC),A0             | A0 = mode dispatch table
        ADDA.W  0(A0,D2.W),A0                   | D2.W),A0 += 0(A0
        RTS                                     | return with A0 = handler
SLABMODE_TBL:
        ORI.B   #0x2E,(A4)+                     | (A4)+ |= 0x2E
        ORI     #0x54,D0                        | (data: dispatch entry encoded as opcode)
SLABMODE_HANDLERS:
        AND     D3,D1                           | COMBINE RIGHT AND LEFT MASK
SLAB_NEXT8:
        MOVE    D6,D0                           | GET PATTERN DATA
        AND     (A2)+,D1                        | mask pattern with edge mask
        AND     D1,D0                           | isolate src bits inside mask
        NOT     D1                              | invert mask for dst-keep
        AND     (A1),D1                         | keep dst bits outside mask
        OR      D0,D1                           | merge src and kept dst
        MOVE    D1,(A1)+                        | UPDATE DST
        MOVEQ.L #-0x1,D1                        | reset mask for next word
        SUBQ.W  #0x1,D2                         | decrement word count
        BGT.B   SLAB_NEXT8                      | more words -> loop
        BEQ.B   SLABMODE_HANDLERS               | last word -> apply edge mask
        RTS                                     | done
SLAB_END9:
        AND     D3,D1                           | srcOr last word: apply edge mask
SLAB_NEXT9:
        AND     D6,D1                           | srcOr: AND mask with pattern
        AND     (A2)+,D1                        | AND with bg pattern lookup
        OR      D1,(A1)+                        | OR result into dst (srcOr)
        MOVEQ.L #-0x1,D1                        | reset mask for next word
        SUBQ.W  #0x1,D2                         | decrement word count
        BGT.B   SLAB_NEXT9                      | more words -> loop
        BEQ.B   SLAB_END9                       | last word -> apply edge mask
        RTS                                     | done
SLAB_END10:
        AND     D3,D1                           | srcXor last word: apply edge mask
SLAB_NEXT10:
        AND     D6,D1                           | srcXor: AND mask with pattern
        AND     (A2)+,D1                        | AND with bg pattern lookup
        EOR     D1,(A1)+                        | XOR into dst (srcXor)
        MOVEQ.L #-0x1,D1                        | reset mask for next word
        SUBQ.W  #0x1,D2                         | decrement word count
        BGT.B   SLAB_NEXT10                     | more words -> loop
        BEQ.B   SLAB_END10                      | last word -> apply edge mask
        RTS                                     | done
SLAB_END11:
        AND     D3,D1                           | srcBic last word: apply edge mask
SLAB_NEXT11:
        AND     D6,D1                           | srcBic: AND mask with pattern
        AND     (A2)+,D1                        | AND with bg pattern lookup
        NOT     D1                              | invert for bit-clear
        AND     D1,(A1)+                        | clear bits in dst (srcBic)
        MOVEQ.L #-0x1,D1                        | reset mask for next word
        SUBQ.W  #0x1,D2                         | decrement word count
        BGT.B   SLAB_NEXT11                     | more words -> loop
        BEQ.B   SLAB_END11                      | last word -> apply edge mask
        RTS                                     | done


