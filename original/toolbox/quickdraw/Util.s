| QuickDraw Utility (ROM $533A-$5745).
|
| Note on cross-subsystem leakage in this file's head:
|
| $533A-$5347 (14 B) -- unreferenced Font Manager cursor stub (below).
| Looks like dead code left over from an earlier
| SetCursor path. Related Font Manager routines
| live in toolbox/font_mgr.s.
|
| $5348-$536A (34 B) -- FMQD_BuildCursorParms* -- Font Manager
| helpers that tail-call through J-vectors
| (JSetCrsr, JInitCrsr, JHideCursor) resolved
| at runtime from low-memory proc pointers.
| Reachable only from the Font Manager; logical
| home is toolbox/font_mgr.s, but the bytes
| sit here at $5348 and moving them would
| re-order QuickDraw.
|
| $536E-$53A3 (54 B) -- DrawControls -- _DrawControls ($A969) trap
| handler. Control Manager code assembled
| inside the QuickDraw Util segment by the
| original ROM layout; the rest of the Control
| Manager lives in toolbox/control_mgr.s.
|
| $53A4+ -- real QuickDraw Util begins (DRAWCONTROLS_EXIT,
| BitNot, LeftMask, MASKTAB, PatExpand, etc.).
|
| ----------------------------------------------------------
| Unreferenced 14-byte Font Manager cursor stub @ $533A-$5347
| (see banner above for why this is here).
| ----------------------------------------------------------
        MOVEA.L (A5),A0                         | A0 = QuickDraw globals base
        PEA.L   -0x6C(A0)                       | push &QDGlobals-0x6C
        JSR     FMQD_BuildCursorParms(PC)       | build cursor param block + call JSetCrsr
        JMP     InitCursor(PC)                  | tail-jump to JInitCrsr vector ($B25C)
FMQD_BuildCursorParms:
        MOVEA.L 4(SP),A0                        | A0 := arg (rect pointer?)
        MOVE    0x42(A0),-(SP)                  | push word @ +0x42
        MOVE    0x40(A0),-(SP)                  | push word @ +0x40
        MOVE    #0x10,-(SP)                     | push constant 16
        PEA.L     (A0)                          | jump via A0
        PEA.L     0x20(A0)                      | push cursor data (offset $20 in struct)
        JSR     SetCursor(PC)                   | call SetCursor (J-vector or local)
        MOVE.L  (SP)+,(SP)                      | pop arg, leave return address
        RTS                                     | return to caller
FMQD_HideCursor:
        JMP     HideCursor(PC)                  | tail-jump to HideCursor (J-vector)
FMQD_ShowCursor:
        JMP     ShowCursor(PC)                  | tail-jump to ShowCursor (J-vector)

| ----------------------------------------------------------
| _DrawControls ($A969)
| Called during boot.
DrawControls:
        LINK    A6,#0x0                         | set up frame (no locals)
        MOVEM.L D0-D2/A0-A1,-(SP)               | save scratch registers
        MOVE.L  12(A6),A0                       | A0 = WindowPtr arg
        MOVE    2(A0),D0                        | D0 = window left in port coords
        SUB.W    10(FP),D0                      | shift to global coords
        MOVE    D0,-(SP)                        | push left for ShieldCursor rect
        MOVE    (A0),D0                         | D0 = window top
        SUB     8(A6),D0                        | jump via A0
        MOVE    D0,-(SP)                        | push top for ShieldCursor rect
        MOVE    6(A0),D0                        | D0 = window right
        SUB     10(A6),D0                       | shift to global coords
        MOVE    D0,-(SP)                        | push right for ShieldCursor rect
        MOVE    4(A0),D0                        | D0 = window bottom
        SUB     8(A6),D0                        | shift to global coords
        MOVE    D0,-(SP)                        | GET COUNT
        JSR     ShieldCursor(PC)                | shield cursor over draw rect
DRAWCONTROLS_EXIT:
        MOVEM.L (SP)+,D0-D2/A0-A1               | restore scratch registers
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        ADDQ.W  #0x8,SP                         | pop two longwords (window args)
        JMP     (A0)                            | RTS
        JMP     ObscureCursor(PC)               | tail-jump to obscure cursor

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
        MOVE.L  (SP)+,A0                        | BitTst: pop return addr
        MOVE.L  (SP)+,D1                        | D1 = bit number
        MOVE    D1,D0                           | D0 = copy of bit num
        ASR.L   #0x3,D1                         | D1 = byte offset (bits / 8)
        NOT     D0                              | reverse bit sense (BTST counts from LSB)
        MOVE.L  (SP)+,A1                        | GET PTR
        BTST    D0,0(A1,D1.L)                   | test bit D0 of 0(A1,D1.L)
        SNE     (SP)                            | SET OR CLEAR RESULT
        NEG.B   (SP)                            | (SP) = -(SP)
        JMP     (A0)                            | RTS
        MOVE.L  (SP)+,A0                        | BitSet: pop return addr
        MOVE.L  (SP)+,D1                        | D1 = bit number
        MOVE    D1,D0                           | D0 = copy of bit num
        ASR.L   #0x3,D1                         | D1 = byte offset (bits / 8)
        NOT     D0                              | reverse bit sense
        MOVE.L  (SP)+,A1                        | GET PTR
        BSET    D0,0(A1,D1.L)                   | SET THE BIT
        JMP     (A0)                            | RTS
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,D1                        | GET BITNUM
        MOVE    D1,D0                           | COPY IT
        ASR.L   #0x3,D1                         | D1 = byte offset (bits / 8)
        NOT     D0                              | REVERSE BIT SENSE
        MOVE.L  (SP)+,A1                        | A1 = byte pointer
        BCLR    D0,0(A1,D1.L)                   | clear bit at byte offset
        JMP     (A0)                            | RTS
        MOVE.L  (A5),A0                         | A0 = QuickDraw globals
        MOVE    #0x41A7,D0                      | D0 = a = 16807 (7^5)
        MULU    -0x7C(A0),D0                    | D0 = D0 *u -0x7C(A0)
        MOVE.L  D0,D1                           | COPY xalo
        CLR     D1                              | zero low word of D1
        SWAP    D1                              | GET HiWord(xalo) as a long
        MOVE    #0x41A7,D2                      | D2 = a = 16807 again
        MULU    -0x7E(A0),D2                    | D2 = D2 *u -0x7E(A0)
        ADD.L   D1,D2                           | ADD LEFTLO = FHI
        MOVE.L  D2,D1                           | COPY FHI
        ADD.L   D1,D1                           | CALC 2 TIMES FHI
        CLR     D1                              | zero low word of D1
        SWAP    D1                              | CALC FHI SHIFTED RIGHT 15 FOR K
        ANDI.L  #0xFFFF,D0                      | isolate low word of XALO
        SUBI.L  #0x7FFFFFFF,D0                  | subtract long imm: 0x7FFFFFFF,D0
        ANDI.L  #0x7FFF,D2                      | isolate low 15 bits of FHI
        SWAP    D2                              | TIMES 64K
        ADD.L   D1,D2                           | PLUS K
        ADD.L   D2,D0                           | CALC TOTAL
        BPL.B   RANDOM_UPDATE                   | if non-negative, skip P add-back
        ADDI.L  #0x7FFFFFFF,D0                  | add long imm: 0x7FFFFFFF,D0
RANDOM_UPDATE:
        MOVE.L  D0,-0x7E(A0)                    | UPDATE SEED
        CMPI    #-0x8000,D0                     | IS NUMBER -32768 ?
        BNE.B   RANDOM_UPDATE_NO                | NO, CONTINUE
        CLR     D0                              | YES, RETURN ZERO INSTEAD
RANDOM_UPDATE_NO:
        MOVE    D0,4(SP)                        | return low word as Pascal result
        RTS                                     | AND RETURN
        MOVEQ.L #0x50,D0                        | ForeColor: D0 = fgColor offset ($50)
        JMP     L_mPortLong(PC)                 | install long into thePort
        MOVEQ.L #0x54,D0                        | BackColor: D0 = bkColor offset ($54)
        JMP     L_mPortLong(PC)                 | install long into thePort
        MOVEQ.L #0x58,D0                        | ColorBit: D0 = colrBit offset ($58)
        JMP     L_mPortWord(PC)                 | install word into thePort
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
        RTS                                     | RETURN TO CALLER
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
        RTS                                     | RETURN TO CALLER
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
| PROCEDURE PortWord(word: INTEGER);
| INSTALL A WORD INTO CURRENT GRAFPORT. ENTER WITH OFFSET IN D0
| PortWord

| .PROC GetMaskTab,0
| .DEF LeftMask,RightMask,BitMask,MaskTab
| ----------------------------------------------------------
| ASSEMBLY LANGUAGE CALLABLE PROCEDURES LEFTMASK, RIGHTMASK, AND BITMASK:
| ENTER WITH COORDINATE IN D0, RETURNS WITH 16 BIT MASK IN D0
| NO OTHER REGISTERS ALTERED.
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
| Returns TRUE if pixel at (h,v) is black. Plus equivalent: Util.s 573.
GetPixel:
        JSR     FMQD_HideCursor(PC)             | GET RID OF CURSOR
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
        JMP     FMQD_ShowCursor(PC)             | RESTORE CURSOR AND RETURN
        MOVE.L  4(SP),A0                        | A0 = arg pointer (skip return addr)
        MOVE.L  (SP)+,(SP)                      | pop return addr, overwrite arg slot
        JMP     (A0)                            | RTS
| ----------------------------------------------------------
| PROCEDURE StuffHex(thingPtr: Ptr; hexStr: Str255);
| Convert a hex string to bytes and stuff into thingPtr. No
| range-checking. Plus equivalent: Util.s 602.
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
