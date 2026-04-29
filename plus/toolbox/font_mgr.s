| Font Manager
|
| Manages font resources and provides font metrics for QuickDraw
| text drawing. Handles font scaling, style variations (bold,
| italic, underline, outline, shadow), and font substitution.
|
| References:
| Inside Macintosh Vol I, Ch 7: The Font Manager
| Inside Macintosh Vol IV, Ch 5: Font Manager additions
| _InitFonts ($A8FE): initialize the Font Manager
| Called during boot to set up font globals and load system font.
InitFonts:
        MOVE.L  D3,-(SP)                        | save D3
        CLR     (FOutError).w                   | clear font output error
        MOVEQ.L #-0x1,D0                        | D0 = -1 (invalid sentinel)
        MOVE    D0,(CurFMFamily).w              | invalidate cached font family
        CLR.L   (LastFOND).w                    | clear last FOND handle
        MOVE    D0,(FONDID).w                   | invalidate FOND ID cache
        BSR     SWAPFONT_OK_16                  | init FMgrOutRec
        CLR     (CurFMDevice).w                 | current device = screen
        CLR.B   (FScaleDisable).w               | enable font scaling
| set application font from PRAM
        MOVE    (SPFont).w,(ApFontID).w         | application font = PRAM setting
        ADDQ.W  #0x1,(ApFontID).w               | adjust to 1-based font ID
| load system font (FONT resource)
        MOVEQ.L #0xC,D0                         | 12 = default size (Chicago 12)
        MOVE    D0,(GotStrike).w                | default font strike size
        MOVE    (SysFontFam).w,D3               | D3 = system font family (0=Chicago)
        ASL     #0x7,D3                         | shift family to high bits
        MOVE    (SysFontSize).w,D1              | D1 = system font size
        BNE.B   INITFONTS_CONT                  | nonzero ->
        MOVE    D0,D1                           | default to 12pt
INITFONTS_CONT:
        OR      D1,D3                           | D3 = fontID (family<<7 | size)
        BSR     SWAPFONT_RETRY_2                | look up FONT resource
        BNE.B   INITFONTS_FOUND                 | found ->
        MOVEQ.L #0xC,D3                         | fallback: FONT 12 (Chicago 12)
        BSR     SWAPFONT_RETRY_2                | try again
INITFONTS_FOUND:
        MOVE.L  A0,(ROMFont0).w                 | save system font handle
        MOVE.L  (SP)+,D3                        | restore D3
| set up width table for fractional widths
        CLR.B   (FractEnable).w                 | disable fractional widths
        MOVE.L  (WidthTabHandle).w,D0           | width table already allocated?
        BNE.B   INITFONTS_ERR                   | yes ->
        MOVE.L  #0x42E,D0                       | 1070 bytes for width table
        _NewHandleSys                           | allocate in system heap
        BNE.B   INITFONTS_ERR_2                 | failed ->
        MOVE.L  A0,(WidthTabHandle).w           | save width table handle
        CLR.L   (WidthListHand).w               | clear width list
| allocate width list if enough RAM (>= 512K)
        CMPI    #0x2,(MemTop).w                 | at least 512K RAM?
        BLS.B   INITFONTS_ERR                   | no ->
        MOVEQ.L #0x30,D0                        | 48 bytes for width list header
        _NewHandleSysClear                      | allocate zeroed
        BNE.B   INITFONTS_ERR                   | alloc failed ->
        MOVE.L  A0,(WidthListHand).w            | save width list handle
INITFONTS_ERR:
        BSR.B   INITFONTS_CONT_2                | invalidate all width table caches
        MOVE    #0x101,D0                       | trap $A901 (FMSwapFont) toolbox bit set
        _GetTrapAddress                         | get current SwapFont vector
        LEA.L   FMSwapFont(PC),A1               | A1 = ROM FMSwapFont entry
        CMPA.L  A1,A0                           | still pointing to ROM default?
        BNE.B   INITFONTS_NO                    | no, app patched it -> keep theirs
        LEA.L   SwapFont(PC),A0                 | use internal SwapFont implementation
INITFONTS_NO:
        MOVE.L  A0,(JSwapFont).w                | install SwapFont vector
        RTS                                     | return from InitFonts

| ----------------------------------------------------------
|
| INITFONTS_ERR_2
|
INITFONTS_ERR_2:
        MOVEQ.L #0x19,D0                        | dsMemFullErr (25): out of memory
        _SysError                               | fatal: can't allocate width table
| INITFONTS_CONT_2: invalidate all width table caches
| Sets font handle and FMInput fields to -1 so next SwapFont reloads
INITFONTS_CONT_2:
        MOVEQ.L #-0x1,D2                        | D2 = -1 (invalid sentinel)
        MOVE.L  D2,(LastSPExtra).w              | invalidate cached spExtra
        MOVE.L  (WidthListHand).w,D0            | width list handle
        AND.L   (Lo3Bytes).w,D0                 | strip flags to get pointer
        BEQ.B   INITFONTS_DONE                  | no width list ->
        MOVE.L  D0,A0                           | A0 = width list pointer
        MOVE.L  (A0),A0                         | dereference master pointer
        MOVEQ.L #0xB,D1                         | 12 width table cache slots
INITFONTS_LOOP:
        MOVE.L  (A0)+,D0                        | D0 = next cache entry handle
        BEQ.B   INITFONTS_DONE                  | empty slot, done ->
        MOVE.L  D0,A1                           | A1 = cache handle
        MOVE.L  (A1),D0                         | dereference handle
        BEQ.B   INITFONTS_SKIP                  | purged, skip ->
        MOVE.L  D0,A1                           | A1 = cache data pointer
        MOVE.L  D2,0x400(A1)                    | invalidate cached font handle
        MOVE    D2,0x40C(A1)                    | invalidate cached FMInput family
INITFONTS_SKIP:
        DBF     D1,INITFONTS_LOOP               | loop through all 12 slots
INITFONTS_DONE:
        MOVE.L  (WidthTabHandle).w,A0           | current width table
        MOVE.L  (A0),A0                         | dereference
        MOVE.L  D2,0x400(A0)                    | invalidate cached font handle
        MOVE    D2,0x40C(A0)                    | invalidate cached FMInput family
        RTS                                     | return from INITFONTS_CONT_2

| ----------------------------------------------------------
|
| _FMSwapFont ($A901)
|
| _FMSwapFont ($A901): swap in a new font - most frequently called FM trap
| A0 = ptr to FMInput record (family, size, face, needBits, device, numer, denom)
| Returns: ptr to FMOutput record with font metrics and strike pointer
FMSwapFont:
        MOVE.L  (JSwapFont).w,-(SP)             | vectored through JSwapFont
        RTS                                     | jump to SwapFont implementation

| ----------------------------------------------------------
|
| SwapFont: actual implementation (37,171 calls in 30s boot trace)
| Checks if requested font matches current cache, loads new strike if not
|
SwapFont:
        LEA.L   (FOutError).w,A0                | A0 = FMOutput record (shares FOutError)
        MOVE.L  A0,0x8(SP)                      | store FMOutput ptr in return value slot
| SWAPFONT_CONT: fast-path cache check - compare FMInput with cached state
SWAPFONT_CONT:
        MOVE.L  (WidthTabHandle).w,A0           | dereference width table
        MOVE.L  (A0),(WidthPtr).w               | cache width table pointer
        MOVE.L  0x4(SP),A0                      | A0 = FMInput record from caller
        LEA.L   (CurFMFamily).w,A1              | A1 = cached FMInput state
| compare 16 bytes: family(2)+size(2)+face(2)+needBits(2)+device(2)+numer(4)+denom(4)
        CMPM.L  (A0)+,(A1)+                     | compare family+size
        BNE.B   SWAPFONT_OK                     | mismatch, need new font ->
        CMPM.L  (A0)+,(A1)+                     | compare face+needBits
        BNE.B   SWAPFONT_OK                     | mismatch, need new font ->
        CMPM.L  (A0)+,(A1)+                     | compare device+numer.v
        BNE.B   SWAPFONT_OK                     | mismatch, need new font ->
        CMPM.L  (A0)+,(A1)+                     | compare numer.h+denom
        BNE.B   SWAPFONT_OK                     | mismatch, need new font ->
| cache hit - check if spExtra changed (affects width calculations)
        MOVE.L  (A5),A0                         | QD globals
        MOVE.L  (A0),A0                         | dereference
        MOVE.L  (LastSPExtra).w,D0              | cached spExtra
        CMP.L   0x4C(A0),D0                     | matches current?
        BEQ.B   SWAPFONT_EXIT                   | yes, full cache hit ->
        ADDQ.L  #0x1,D0                         | was it -1 (uninitialized)?
        BEQ.B   SWAPFONT_OK                     | yes, need full recalc ->
| spExtra changed: just recalculate widths, don't reload font
        MOVE.L  0x4(SP),D0                      | D0 = FMInput ptr from caller
        MOVEM.L D3-D7/A3-A4,-(SP)               | save registers
        MOVE.L  D0,A3                           | A3 = FMInput record
        BRA     SWAPFONT_NO_4                   | -> recalc widths only

| ----------------------------------------------------------
|
| SWAPFONT_OK
|
| SWAPFONT_OK: cache miss - need to load new font
| Called during boot (1,663 times in 30s trace).
SWAPFONT_OK:
        MOVEM.L A3-A4,-(SP)                     | save regs for slow path
        MOVE.L  0xC(SP),A3                      | A3 = FMInput record from caller
        BRA     SWAPFONT_CONT_14                | -> slow path: find and load font

| ----------------------------------------------------------
|
| SWAPFONT_EXIT
|
| SWAPFONT_EXIT: SwapFont exit - verify font handle still valid before returning
| Called during boot (37,171 times in 30s trace).
SWAPFONT_EXIT:
        MOVE.L  (FOutFontHandle).w,A0           | A0 = current font handle
        TST.B   (A0)                            | check master pointer flags
        BNE.B   SWAPFONT_EXIT_2                 | nonzero (valid, locked) -> return
        TST.L   (A0)                            | master pointer nil (purged)?
        BNE.B   SWAPFONT_OK                     | no, just unlocked -> full recache
| font was purged - try to reload it
        MOVE.L  A0,-(SP)                        | push handle for LoadResource
        MOVE    #-0x1,(ROMMapInsert).w          | include ROM map
        _LoadResource                           | try to reload
        TST     (ResErr).w                      | load succeeded?
        BNE.B   SWAPFONT_RETRY                  | no -> rebuild FMInput and retry
        BSR     INVERTCOLOR_CONT_3              | rebuild glyph bbox table
        BRA.B   SWAPFONT_EXIT_2                 | -> return

| ----------------------------------------------------------
|
| SWAPFONT_RETRY: font reload failed - build synthetic FMInput and retry via SWAPFONT_CONT
|
SWAPFONT_RETRY:
        MOVEQ.L #0x10,D0                        | 16 bytes for FMInput copy
        SUBA.L  D0,SP                           | allocate on stack
        MOVE.L  A7,A1                           | A1 = dest (stack FMInput)
        LEA.L   (CurFMFamily).w,A0              | A0 = cached FMInput
        _BlockMove                              | copy 16 bytes
        CLR     (SP)                            | force family = 0 (system font)
        MOVE.L  A7,-(SP)                        | push FMInput ptr as parameter
  .short 0x6180                                 | Bsr.B SWAPFONT_CONT (re-enter cache check)
        ADDA    #0x10,SP                        | pop stack FMInput
| SWAPFONT_EXIT_2: SwapFont return - pop saved regs and jump to return address
SWAPFONT_EXIT_2:
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x4,SP                         | strip FMInput pointer param
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| SWAPFONT_CONT_2
|
| SWAPFONT_CONT_2: apply font style modifications from FMStyleTab
| Called during boot (1,663 times in 30s trace).
SWAPFONT_CONT_2:
        MOVE.B  (FOutUnused).w,D1               | D1 = style bits (bold/italic/etc)
        LEA.L   (FOutBold).w,A0                 | clear style output fields
        CLR.L   (A0)+                           | clear bold+italic offsets
        CLR     (A0)+                           | clear ULOffset+ULShadow
        CLR.B   (A0)+                           | clear ULThick
        TST.B   D1                              | any style bits set?
        BEQ.B   SWAPFONT_SKIP_2                 | plain text, skip ->
        MOVEQ.L #0x0,D2                         | D2 = style table field index
        LEA.L   (FMStyleTab).w,A1               | A1 = style modification table
        MOVEQ.L #0x6,D0                         | 7 style entries to process
        LEA.L   (FOutBold).w,A0                 | A0 = output style fields base
SWAPFONT_LOOP:
        MOVE.B  (A1)+,D2                        | D2 = field offset in FMOutput
        MOVE.B  (A1)+,D3                        | D3 = addend for that field
        MOVE.B  (A1)+,D4                        | D4 = extra width addend
        LSR     #0x1,D1                         | shift out lowest style bit
        BCC.B   SWAPFONT_SKIP                   | bit was 0, skip this style ->
        ADD.B   D3,0x0(A0,D2.W)                 | accumulate style offset
        ADD.B   D4,(FOutExtra).w                | accumulate extra width
SWAPFONT_SKIP:
        DBF     D0,SWAPFONT_LOOP                | next style entry
        BTST    #0x2,0x4(A3)                    | underline style requested?
        BEQ.B   SWAPFONT_SKIP_2                 | no ->
        LEA.L   (FOutULOffset).w,A0             | A0 = underline output fields
        MOVE.B  (A1)+,(A0)+                     | copy UL offset from table
        MOVE.B  (A1)+,(A0)+                     | copy UL shadow
        MOVE.B  (A1)+,(A0)+                     | copy UL thickness
SWAPFONT_SKIP_2:
        MOVE.L  (WidthTabHandle).w,A0           | get width table handle
        MOVE.L  (A0),A0                         | dereference
        MOVE.L  A0,(WidthPtr).w                 | cache dereferenced pointer
        MOVE.L  (LastFOND).w,D0                 | FOND resource loaded?
        BEQ.B   SWAPFONT_NO                     | no FOND, use integer widths ->
        TST.B   (FDevDisable).w                 | device widths disabled?
        BNE.B   SWAPFONT_OK_2                   | yes ->
        TST     0x6(A3)                         | FMInput.device nonzero (printer)?
        BNE.B   SWAPFONT_NO                     | printer device, use integer widths ->
SWAPFONT_OK_2:
        BTst    #0x4,(WidthListHand).w          | FOND has width table offset?
        BNE.B   SWAPFONT_OK_3                   | yes, use FOND widths ->
        TST.B   (FractEnable).w                 | fractional widths enabled?
        BEQ.B   SWAPFONT_NO                     | no, use integer widths ->
SWAPFONT_OK_3:
        BTst    #0x5,(WidthListHand).w          | FOND has style width table?
        BEQ     SWAPFONT_NO_10                  | no -> compute from FOND widths
| SWAPFONT_NO: build width table from font strike's offset/width table
SWAPFONT_NO:
        MOVEQ.L #0x0,D6                         | D6 = extra width in 16.16 fixed
        MOVE.B  (FOutExtra).w,D6                | load style extra width (signed byte)
        EXT     D6                              | sign-extend to word
        SWAP    D6                              | move to high word (integer part)
SWAPFONT_OK_4:
        MOVE    PORTBITS(A3),D1                 | D1 = current port's rowBytes
        LEA.L   0x400(A0),A1                    | A1 = width table cache header
        MOVE.L  (FOutFontHandle).w,D0           | D0 = current font handle
        CMP.L   (A1),D0                         | same font as cached?
        BNE.B   SWAPFONT_NO_2                   | no, rebuild width table ->
        CMP     0x40E(A0),D1                    | same rowBytes (same port)?
        BEQ     SWAPFONT_OK_8                   | yes, just update extra ->
SWAPFONT_NO_2:
        MOVE.L  D0,(A1)+                        | store font handle in cache header
        CLR.L   (A1)+                           | clear cached spExtra
        MOVE.L  D6,(A1)                         | store extra width
        ADDA    #0x14,A1                        | skip to FOND info area at +$418
        MOVE    (FONDID).w,(A1)+                | store FOND ID in cache
        MOVE.L  (LastFOND).w,(A1)               | store FOND handle in cache
        MOVE.L  D0,A0                           | A0 = font handle
        BSR     SWAPFONT_CONT_20                | dereference + ensure loaded -> A0=ptr
        MOVE.L  A0,A1                           | A1 = font strike data pointer
        MOVEM   (A0),D2-D4                      | D2=fontType, D3=firstChar, D4=lastChar
        MOVE    D4,D5                           | D5 = lastChar
        SUB     D3,D5                           | D5 = char range (last-first)
        MOVE    D5,D1                           | D1 = char range (loop counter)
        ADDQ.W  #0x3,D5                         | +3 for missing char + 2 entries
        ADD     D5,D5                           | *2 bytes per offset/width entry
        EXT.L   D5                              | sign-extend to long
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE    0x10(A0),D0                     | D0 = rowWords (words per bitmap row)
        ADDQ.L  #0x8,D0                         | + 8 for header words
        ADD.L   D0,D0                           | *2 bytes per word = byte offset
        ADDA.L  D0,A1                           | A1 = offset/width table in strike
        MOVEQ.L #0x0,D7                         | D7 = default (missing) char width
        TST.B   (FractEnable).w                 | fractional widths enabled?
        BEQ.B   SWAPFONT_NO_3                   | no -> use integer widths
        BTST    #0x1,D2                         | font has fixed-point widths?
        BNE.B   SWAPFONT_OK_5                   | yes -> use 16-bit widths
        BTST    #0x6,(WidthListHand).w          | FOND has width table?
        BNE.B   SWAPFONT_NO_3                   | yes -> use those instead
        MOVE.L  A4,D0                           | A4 = FOND width subtable offset
        BEQ.B   SWAPFONT_NO_3                   | no subtable ->
        MOVE.L  (LastFOND).w,A1                 | get FOND handle
        MOVE.L  (A1),A1                         | dereference FOND
        ADDA.L  A4,A1                           | A1 = width subtable in FOND
        BRA     SWAPFONT_CONT_12                | -> use FOND fractional widths

| ----------------------------------------------------------
|
| SWAPFONT_NO_3
|
| SWAPFONT_NO_3: get missing symbol width from integer offset/width table
| Called during boot.
SWAPFONT_NO_3:
        MOVE.B  -0x3(A1,D5.W),D7                | D7 = missing char width (8-bit)
        SWAP    D7                              | move to high word (16.16 fixed)
        BRA.B   SWAPFONT_CONT_3                 | -> apply scaling

| ----------------------------------------------------------
|
| SWAPFONT_OK_5
|
| SWAPFONT_OK_5: get missing symbol width from 16-bit fixed-point width table
SWAPFONT_OK_5:
        ADDA.L  D5,A1                           | skip past offset table to width table
        MOVE    -0x4(A1,D5.W),D7                | D7 = missing char width (16-bit frac)
        ASL.L   #0x8,D7                         | convert 8.8 to 16.16 fixed point
| SWAPFONT_CONT_3: apply horizontal scaling to missing char width
SWAPFONT_CONT_3:
        CMPI.L  #0x10000,(FScaleHFact).w        | scale factor == 1.0?

        SNE.B   D5                              | D5 = $FF if scaling needed
        AND.B   (FScaleDisable).w,D5            | mask with scale disable flag
        ADD.L   D6,D7                           | add extra width from style
        MOVE.L  D7,D0                           | D0 = width to scale
        BSR     SWAPFONT_CONT_8                 | apply horizontal scale if needed
        MOVE.L  D0,D7                           | D7 = scaled missing char width
        MOVE.L  (WidthPtr).w,A0                 | A0 = width table data pointer
        BRA.B   SWAPFONT_LOOP_3                 | -> begin fill loop

| ----------------------------------------------------------
|
| SWAPFONT_LOOP_2
|
SWAPFONT_LOOP_2:
        MOVE.L  D7,(A0)+                        | fill width for chars below firstChar
SWAPFONT_LOOP_3:
        DBF     D3,SWAPFONT_LOOP_2              | loop firstChar times
        CLR.B   (UsedFWidth).w                  | flag: not using fractional widths
        TST.B   (FractEnable).w                 | fractional widths enabled?
        BEQ.B   SWAPFONT_LOOP_4                 | no -> use integer widths
        BTST    #0x1,D2                         | font has 16-bit widths?
        BNE.B   SWAPFONT_LOOP_6                 | yes -> use 16-bit width table
        BTST    #0x6,(WidthListHand).w          | FOND has width table?
        BNE.B   SWAPFONT_LOOP_4                 | yes -> use FOND widths at SWAPFONT_LOOP_4
        MOVE.L  A4,D0                           | FOND width subtable offset?
        BNE     SWAPFONT_OK_6                   | yes -> use FOND fractional widths
| SWAPFONT_LOOP_4: build width table from 8-bit offset/width entries
SWAPFONT_LOOP_4:
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE    (A1)+,D3                        | D3 = offset/width word for this char
        BPL.B   SWAPFONT_CONT_4                 | valid entry (high bit clear) ->
        MOVE.L  D7,D0                           | missing char: use default width
        BRA.B   SWAPFONT_CONT_5                 | -> store it

| ----------------------------------------------------------
|
| SWAPFONT_CONT_4
|
| SWAPFONT_CONT_4: extract 8-bit width from low byte, scale it
| Called during boot.
SWAPFONT_CONT_4:
        MOVE.B  D3,D0                           | D0.B = char width (low byte)
        SWAP    D0                              | move to high word (16.16 fixed)
        ADD.L   D6,D0                           | add extra width from style
        BSR.B   SWAPFONT_CONT_8                 | apply horizontal scale if needed
SWAPFONT_CONT_5:
        MOVE.L  D0,(A0)+                        | store 16.16 fixed-point width
        DBF     D1,SWAPFONT_LOOP_4              | next char in range
| SWAPFONT_CONT_6: fill widths for chars above lastChar (codes 256+)
SWAPFONT_CONT_6:
        SUBI    #0xFF,D4                        | D4 = lastChar - 255
        BEQ.B   SWAPFONT_NO_4                   | lastChar==255, no fill needed ->
        NEG     D4                              | D4 = 255 - lastChar
        SUBQ.W  #0x1,D4                         | adjust for DBF
SWAPFONT_LOOP_5:
        MOVE.L  D7,(A0)+                        | fill with missing char width
        DBF     D4,SWAPFONT_LOOP_5              | loop remaining entries
SWAPFONT_NO_4:
        MOVE.L  (WidthPtr).w,A1                 | A1 = width table base
        ADDA    #0x408,A1                       | A1 = spExtra adjustment field
        BRA     SWAPFONT_NO_7                   | -> apply spExtra and finish

| ----------------------------------------------------------
|
| SWAPFONT_LOOP_6: build width table from 16-bit fixed-point width entries
|
SWAPFONT_LOOP_6:
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE    (A1)+,D3                        | D3 = 16-bit fixed-point width
        CMPI    #-0x1,D3                        | missing char sentinel ($FFFF)?
        BNE.B   SWAPFONT_NO_5                   | no, valid width ->
        MOVE.L  D7,D0                           | use default missing char width
        BRA.B   SWAPFONT_CONT_7                 | -> store it

| ----------------------------------------------------------
|
| SWAPFONT_NO_5: scale 16-bit fixed-point char width
|
SWAPFONT_NO_5:
        MOVE    D3,D0                           | D0 = 8.8 fixed-point width
        ASL.L   #0x8,D0                         | convert to 16.16 fixed point
        ADD.L   D6,D0                           | add style extra width
        BSR.B   SWAPFONT_CONT_8                 | apply horizontal scale if needed
SWAPFONT_CONT_7:
        MOVE.L  D0,(A0)+                        | store 16.16 fixed-point width
        DBF     D1,SWAPFONT_LOOP_6              | next char in range
        ST.B    (UsedFWidth).w                  | flag: using fractional widths
        BRA.B   SWAPFONT_CONT_6                 | -> fill chars above lastChar

| ----------------------------------------------------------
|
| SWAPFONT_CONT_8: conditionally apply horizontal scaling to width in D0
| D5 = nonzero if scaling needed, D0 = 16.16 fixed-point width
|
| Called during boot.
SWAPFONT_CONT_8:
        TST.B   D5                              | scaling needed?
        BEQ.B   SWAPFONT_EXIT_3                 | no -> return unchanged
        MOVEM.L D0-D1/A0-A1,-(SP)               | save regs
        MOVE.L  D0,-(SP)                        | push width value
        MOVE.L  (FScaleHFact).w,-(SP)           | push horizontal scale factor
        BSR     SWAPFONT_CONT_24                | FixMul: width * scale
        MOVEM.L (SP)+,D0-D1/A0-A1               | restore regs (D0 = scaled result)
SWAPFONT_EXIT_3:
        RTS                                     | return from SWAPFONT_CONT_8

| ----------------------------------------------------------
|
| SWAPFONT_OK_6
|
| SWAPFONT_OK_6: build widths from FOND width subtable with per-point scaling
SWAPFONT_OK_6:
        MOVE.L  A0,-(SP)                        | save width table pointer
        MOVE.L  (WidthPtr).w,A0                 | get width table
        MOVE    0x42C(A0),D0                    | D0 = font-to-point scale factor
        MOVE.L  (SP)+,A0                        | restore width table pointer
        MOVE    D0,-(SP)                        | push scale factor for loop
SWAPFONT_LOOP_7:
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE    (A1)+,D3                        | D3 = FOND width entry (4.12 fixed)
        CMPI    #-0x1,D3                        | missing char sentinel?
        BNE.B   SWAPFONT_NO_6                   | no, valid ->
        MOVE.L  D7,D0                           | use default missing char width
        BRA.B   SWAPFONT_CONT_9                 | -> store it

| ----------------------------------------------------------
|
| SWAPFONT_NO_6: scale FOND width by point size factor
|
SWAPFONT_NO_6:
        MOVE    D3,D0                           | D0 = FOND width (4.12 fixed)
        MULU    (SP),D0                         | multiply by point scale factor
        ASL.L   #0x4,D0                         | adjust to 16.16 fixed point
        ADD.L   D6,D0                           | add style extra width
        BSR.B   SWAPFONT_CONT_8                 | apply horizontal scale if needed
SWAPFONT_CONT_9:
        MOVE.L  D0,(A0)+                        | store 16.16 fixed-point width
        DBF     D1,SWAPFONT_LOOP_7              | next char in range
        ADDQ.W  #0x2,SP                         | pop scale factor
        ST.B    (UsedFWidth).w                  | flag: using fractional widths
        BRA     SWAPFONT_CONT_6                 | -> fill chars above lastChar

| ----------------------------------------------------------
|
| SWAPFONT_CONT_10
|
| SWAPFONT_CONT_10: determine effective font size
| Returns D0 = font size: from FMInput.size, SysFontSize, or FMDefaultSize
| Called during boot.
SWAPFONT_CONT_10:
        MOVE    PORTBITS(A3),D0                 | D0 = FMInput.size (at offset 2)
        BNE.B   SWAPFONT_CONT_11                | explicit size requested ->
        TST     (A3)                            | FMInput.family nonzero?
        BNE.B   SWAPFONT_OK_7                   | yes, use default size ->
        MOVE    (SysFontSize).w,D0              | try system font size
        BNE.B   SWAPFONT_CONT_11                | nonzero ->
SWAPFONT_OK_7:
        MOVE.B  (FMDefaultSize).w,D0            | fall back to default size (12)
SWAPFONT_CONT_11:
        RTS                                     | return font size in D0

| ----------------------------------------------------------
|
| SWAPFONT_CONT_12
|
| SWAPFONT_CONT_12: compute missing char width from FOND width subtable
SWAPFONT_CONT_12:
        MOVE.L  (WidthPtr).w,A0                 | get width table
        MOVE    0x42C(A0),D0                    | D0 = point scale factor
        MOVE    -0x4(A1,D5.W),D7                | D7 = FOND missing char width
        MULU    D0,D7                           | scale by point factor
        ASL.L   #0x4,D7                         | adjust to 16.16 fixed point
        BRA     SWAPFONT_CONT_3                 | -> apply horizontal scaling

| ----------------------------------------------------------
|
| SWAPFONT_OK_8: width table cache hit but extra width changed
| Adjusts all 256 cached widths by the extra delta
|
| Called during boot (1,659 times in 30s trace).
SWAPFONT_OK_8:
        ADDQ.L  #0x8,A1                         | A1 = cached extra width field
        SUB.L   (A1),D6                         | D6 = delta (new extra - old extra)
        BEQ.B   SWAPFONT_NO_7                   | no change ->
        ADD.L   D6,(A1)                         | update cached extra width
        MOVE.L  (WidthPtr).w,A0                 | A0 = width table entries
        MOVE    #0xFF,D0                        | 256 entries to adjust
SWAPFONT_LOOP_8:
        ADD.L   D6,(A0)+                        | adjust each width by delta
        DBF     D0,SWAPFONT_LOOP_8              | loop all 256 chars
| SWAPFONT_NO_7: apply spExtra (space character extra width) adjustment
SWAPFONT_NO_7:
        MOVE.L  (A5),A0                         | QD globals
        MOVE.L  (A0),A0                         | dereference
        MOVE.L  0x4C(A0),D7                     | D7 = current spExtra (16.16 fixed)
        SUBQ.L  #0x4,A1                         | A1 = cached spExtra field in width table
        SUB.L   (A1),D7                         | D7 = delta (new - cached)
        BEQ.B   SWAPFONT_NO_8                   | no change ->
        ADD.L   D7,(A1)                         | update cached spExtra
| scale spExtra delta by numer/denom ratio and add to space char width
        SUBA    #0xC,SP                         | stack space for FixMul chain
        MOVE    0xA(A3),-(SP)                   | push FMInput.numer.h
        MOVE    0xE(A3),-(SP)                   | push FMInput.denom.h
        BSR     SWAPFONT_CONT_25                | FixRatio(numer.h, denom.h)
        SUBQ.W  #0x4,SP                         | space for second ratio
        MOVE    (FOutDenom_v).w,-(SP)           | push output denom.v
        MOVE    (FOutNumer_v).w,-(SP)           | push output numer.v
        BSR     SWAPFONT_CONT_25                | FixRatio(numer.v, denom.v)
        BSR     SWAPFONT_CONT_24                | FixMul: combine ratios
        MOVE.L  D7,-(SP)                        | push spExtra delta
        BSR     SWAPFONT_CONT_24                | FixMul: delta * combined ratio
        MOVE.L  (WidthPtr).w,A0                 | width table data
        MOVE.L  (SP)+,D0                        | D0 = scaled spExtra delta
        ADD.L   D0,0x80(A0)                     | add to space char ($20) width entry
| SWAPFONT_NO_8: notify printer driver of font change if device port active
SWAPFONT_NO_8:
        MOVEQ.L #-0x1,D0                        | init D0 to -1
        MOVE.B  0x6(A3),D0                      | D0 = FMInput.device (driver refNum)
        BEQ.B   SWAPFONT_NO_9                   | no device driver ->
        MOVEQ.L #0x32,D1                        | 50 bytes for param block
        SUBA.L  D1,SP                           | allocate param block on stack
        MOVE.L  A7,A0                           | A0 = param block
        MOVE    D0,0x18(A0)                     | ioRefNum = device driver refNum
        MOVE    #0x8,0x1A(A0)                   | csCode = 8 (font changed notification)
        MOVE.L  A3,0x1C(A0)                     | csParam = FMInput record pointer
        MOVE    0x6(A3),0x20(A0)                | csParam+4 = device ID
        _Control                                | send control call to driver
        ADDA.L  D1,SP                           | pop param block
| SWAPFONT_NO_9: save current FMInput as cached state for fast-path comparison
SWAPFONT_NO_9:
        MOVE.L  A3,A0                           | A0 = FMInput record
        LEA.L   (CurFMFamily).w,A1              | A1 = cached FMInput state
        MOVE.L  (A0)+,(A1)+                     | copy family+size
        MOVE.L  (A0)+,(A1)+                     | copy face+needBits
        MOVE.L  (A0)+,(A1)+                     | copy device+numer.v
        MOVE.L  (A0)+,(A1)+                     | copy numer.h+denom
        MOVE.L  (A5),A0                         | QD globals
        MOVE.L  (A0),A0                         | dereference
        MOVE.L  0x4C(A0),(LastSPExtra).w        | cache current spExtra
        MOVE.L  (WidthPtr).w,A0                 | width table pointer
        MOVE.B  (UsedFWidth).w,0x422(A0)        | save fractional width flag
        MOVE.B  (FOutUnused).w,0x423(A0)        | save style bits in cache
        MOVE    (FONDID).w,0x41C(A0)            | save FOND ID in cache
        MOVE.L  (LastFOND).w,0x41E(A0)          | save FOND handle in cache
        LEA.L   0x40C(A0),A0                    | cache FMInput in width table
        MOVE.L  (A3)+,(A0)+                     | copy 16 bytes of FMInput
        MOVE.L  (A3)+,(A0)+                     | (bytes 5-8)
        MOVE.L  (A3)+,(A0)+                     | (bytes 9-12)
        MOVE.L  (A3),(A0)                       | (bytes 13-16)
        MOVEM.L (SP)+,D3-D7/A3-A4               | restore registers
        BRA     SWAPFONT_EXIT                   | -> return via SWAPFONT_EXIT exit

| ----------------------------------------------------------
|
| SWAPFONT_NO_10
|
| SWAPFONT_NO_10: compute extra width from FOND style width offsets
| FOND at offset $1C has base width + 8 per-style adjustments
SWAPFONT_NO_10:
        MOVEM.L D0-D2/A0,-(SP)                  | save regs
        MOVE.L  (LastFOND).w,A0                 | get FOND handle
        BSR     SWAPFONT_CONT_20                | dereference + ensure loaded
        LEA.L   0x1C(A0),A0                     | A0 = FOND style width table
        MOVEQ.L #0x0,D6                         | D6 = accumulated extra width
        MOVE    (A0)+,D6                        | D6 = base width offset (signed)
        EXT.L   D6                              | sign-extend to long
        MOVE.B  (FOutUnused).w,D1               | D1 = style bits
        BEQ.B   SWAPFONT_SKIP_4                 | no styles -> skip adjustments
        MOVEQ.L #0x7,D0                         | 8 style entries
SWAPFONT_LOOP_9:
        MOVE    (A0)+,D2                        | D2 = per-style width adjustment
        EXT.L   D2                              | sign-extend
        LSR     #0x1,D1                         | shift out lowest style bit
        BCC.B   SWAPFONT_SKIP_3                 | bit not set, skip ->
        ADD.L   D2,D6                           | accumulate style width offset
SWAPFONT_SKIP_3:
        DBF     D0,SWAPFONT_LOOP_9              | next style entry
SWAPFONT_SKIP_4:
        ASL.L   #0x4,D6                         | convert to 4.28 for multiply
        SUBQ.W  #0x4,SP                         | space for FixMul result
        MOVE.L  (WidthPtr).w,A0                 | width table
        MOVE    0x42C(A0),D0                    | D0 = point scale factor
        CLR     -(SP)                           | push high word = 0
        MOVE    D0,-(SP)                        | push scale factor as fixed point
        MOVE.L  D6,-(SP)                        | push accumulated width offset
        BSR     SWAPFONT_CONT_24                | FixMul: width * scale
        MOVE.L  (SP)+,D6                        | D6 = scaled extra width (16.16)
        MOVE.L  D6,D0                           | copy to D0
        SWAP    D0                              | D0 = integer part
        BPL.B   SWAPFONT_NO_11                  | positive -> no rounding
        ADDQ.W  #0x1,D0                         | round negative up toward zero
SWAPFONT_NO_11:
        MOVE.B  D0,(FOutExtra).w                | store computed extra width
        MOVEM.L (SP)+,D0-D2/A0                  | restore regs
        TST.B   (FractEnable).w                 | fractional widths enabled?
        BEQ     SWAPFONT_NO                     | no -> integer width path
        BRA     SWAPFONT_OK_4                   | yes -> fractional width path

| ----------------------------------------------------------
|
| SWAPFONT_CONT_13
|
| SWAPFONT_CONT_13: restore cached numer/denom and scale factor from width table
| D1 = 0 for horizontal, 2 for vertical; A1 = cached values in width table
| Called during boot (3,318 times in 30s trace).
SWAPFONT_CONT_13:
        LEA.L   (FOutNumer_h).w,A0              | A0 = FMOutput numer base
        MOVE    (A1)+,D0                        | D0 = cached numer component
        MOVE    D0,0x0(A0,D1.W)                 | store numer.h or numer.v
        LEA.L   (FScaleVFact).w,A0              | A0 = scale factor base
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE    0x2(A1),D0                      | D0 = cached denom component
        ASL.L   #0x8,D0                         | convert to 16.16 fixed point
        ASL     #0x1,D1                         | double index (long vs word)
        NEG     D1                              | negate: VFact at 0, HFact at -4
        MOVE.L  D0,0x0(A0,D1.W)                 | store scale factor
        RTS                                     | return from SWAPFONT_CONT_13

| ----------------------------------------------------------
|
| SWAPFONT_FOUND
|
| SWAPFONT_FOUND: swap width table cache - exchange current table with one from width list
| A4 = slot in width list array; promotes the cached table to active
| Called during boot (1,661 times in 30s trace).
SWAPFONT_FOUND:
        MOVE.L  (WidthTabHandle).w,D3           | D3 = current active width table
        MOVE.L  (A4),A0                         | A0 = cached width table from list
        MOVE.L  A0,(WidthTabHandle).w           | promote cached to active
        MOVE.L  (A0),(WidthPtr).w               | update dereferenced pointer
        BCLR    #0x6,(A0)                       | mark promoted table non-purgeable
        MOVE.L  D3,(A4)                         | demote old active to cache slot
        MOVE.L  D3,A0                           | A0 = demoted table handle
        BSET    #0x6,(A0)                       | mark demoted table purgeable
        MOVE    #-0x2,(CurFMFamily).w           | invalidate family cache (-2)
        RTS                                     | return from SWAPFONT_FOUND

| ----------------------------------------------------------
|
| SWAPFONT_CONT_14
|
| SWAPFONT_CONT_14: SwapFont slow path - cache miss, must find/load new font
| Called during boot (1,663 times in 30s trace).
SWAPFONT_CONT_14:
        MOVEM.L D3-D7,-(SP)                     | save work registers
        MOVE.B  0x4(A3),(FOutUnused).w          | save face (style) bits from FMInput
        MOVE    0x6(A3),D0                      | D0 = FMInput.device
        CMP     (CurFMDevice).w,D0              | device changed?
        BEQ.B   SWAPFONT_NO_12                  | no ->
        BSR     SWAPFONT_CONT_39                | query device DPI via Status call
SWAPFONT_NO_12:
        MOVE.L  (WidthListHand).w,D0            | width list handle
        AND.L   (Lo3Bytes).w,D0                 | strip flags
        BEQ.B   SWAPFONT_NO_13                  | no width list ->
        MOVE    (CurFMFamily).w,D1              | cached family
        ADDQ.W  #0x1,D1                         | was it -1 (uninitialized)?
        BNE.B   SWAPFONT_NO_14                  | no, try width list cache ->
        BSR     INITFONTS_CONT_2                | invalidate all caches first
SWAPFONT_NO_13:
        BRA     SWAPFONT_NO_15                  | -> full font lookup (no cache)

| ----------------------------------------------------------
|
| SWAPFONT_NO_14
|
| SWAPFONT_NO_14: search width list cache for matching FMInput
| 12 slots, each with a full width table keyed by FMInput
| Called during boot (1,661 times in 30s trace).
SWAPFONT_NO_14:
        MOVE.L  D0,A4                           | A4 = width list pointer
        MOVE.L  (A4),A4                         | dereference width list handle
        MOVEQ.L #0x0,D5                         | D5 = slot index (bytes)
        MOVE.L  #0x42E,D0                       | D0 = width table size (1070 bytes)
SWAPFONT_NEXT:
        MOVE.L  (A4),D1                         | D1 = width table handle in this slot
        BEQ.B   SWAPFONT_EMPTY                  | empty slot -> allocate new one
        MOVE.L  D1,A0                           | A0 = width table handle
        MOVE.L  (A0),D1                         | dereference (check if purged)
        BEQ.B   SWAPFONT_CONT_15                | purged -> reallocate
        MOVE.L  D1,A1                           | A1 = width table data
        MOVE.L  A3,A0                           | A0 = FMInput record
        LEA.L   0x40C(A1),A1                    | A1 = cached FMInput in width table
        CMPM.L  (A0)+,(A1)+                     | compare family+size
        BNE.B   SWAPFONT_NEXT_2                 | mismatch ->
        CMPM.L  (A0)+,(A1)+                     | compare face+needBits
        BNE.B   SWAPFONT_NEXT_2                 | mismatch -> try next slot
        CMPM.L  (A0)+,(A1)+                     | compare device+numer.v
        BNE.B   SWAPFONT_NEXT_2                 | mismatch -> try next slot
        CMPM.L  (A0)+,(A1)+                     | compare numer.h+denom
        BEQ.B   SWAPFONT_FOUND_2                | full match -> use this cache
SWAPFONT_NEXT_2:
        ADDQ.W  #0x4,A4                         | next slot in width list
        ADDQ.W  #0x4,D5                         | advance index
        CMPI    #0x30,D5                        | checked all 12 slots? (12*4=48)
        BCS.B   SWAPFONT_NEXT                   | no -> try next
        SUBQ.W  #0x4,A4                         | back up to last slot (reuse it)
        BRA.B   SWAPFONT_ERR                    | -> swap in last slot

| ----------------------------------------------------------
|
| SWAPFONT_FOUND_2
|
| Called during boot (1,659 times in 30s trace).
SWAPFONT_FOUND_2:
        BSR     SWAPFONT_FOUND                  | make matched cache table active
        MOVE    (A1)+,(FONDID).w                | restore cached FOND ID
        MOVE.L  (A1)+,A0                        | get cached FOND handle
        MOVE.L  A0,(LastFOND).w                 | restore LastFOND global
        BEQ.B   SWAPFONT_SKIP_5                 | if no FOND, skip FOND field restore
        MOVE.L  (A0),A0                         | dereference FOND handle
        MOVE.B  (A0),(WidthListHand).w          | restore FOND flags to WidthListHand (byte)
SWAPFONT_SKIP_5:
        MOVE.B  (A1)+,(UsedFWidth).w            | restore fractional width flag
        MOVE.B  (A1)+,(FOutUnused).w            | restore style bits
        MOVEQ.L #0x0,D1                         | D1 = 0 (horizontal)
        BSR     SWAPFONT_CONT_13                | restore horizontal numer/scale
        MOVEQ.L #0x2,D1                         | D1 = 2 (vertical)
        BSR     SWAPFONT_CONT_13                | restore vertical numer/scale
        MOVE.L  (WidthPtr).w,A1                 | width table data
        MOVE.L  0x400(A1),A0                    | A0 = cached font handle
        MOVE.L  A0,(FOutFontHandle).w           | restore as current font
        BRA.B   SWAPFONT_CONT_18                | -> finish with font metrics

| ----------------------------------------------------------
|
| SWAPFONT_CONT_15: reallocate purged width table cache entry
|
SWAPFONT_CONT_15:
        MOVE.L  (TheZone).w,-(SP)               | save current zone
        MOVE.L  (SysZone).w,(TheZone).w         | switch to system zone
        _ReallocHandle                          | reallocate purged handle
        MOVE.L  (SP)+,(TheZone).w               | restore original zone
        BRA.B   SWAPFONT_CONT_16                | -> initialize new cache entry

| ----------------------------------------------------------
|
| SWAPFONT_EMPTY: allocate new width table cache entry
|
| Called during boot.
SWAPFONT_EMPTY:
        _NewHandleSys                           | allocate 1070 bytes in system heap
        BNE.B   SWAPFONT_ERR                    | failed ->
SWAPFONT_CONT_16:
        MOVE.L  (WidthListHand).w,A4            | re-dereference (may have moved)
        MOVE.L  (A4),A4                         | width list data pointer
        LEA.L   0x0(A4,D5.W),A4                 | A4 = slot for this index
        MOVE.L  A0,(A4)                         | store new handle in slot
        MOVE.L  (A0),A0                         | dereference new table
        MOVEQ.L #-0x1,D0                        | -1 = invalid sentinel
        MOVE.L  D0,0x400(A0)                    | invalidate cached font handle
        MOVE    D0,0x40C(A0)                    | invalidate cached FMInput family
        BRA.B   SWAPFONT_CONT_17                | -> swap into active

| ----------------------------------------------------------
|
| SWAPFONT_ERR: width list full or alloc failed - reuse last slot
|
SWAPFONT_ERR:
        TST     D5                              | slot index 0?
        BEQ.B   SWAPFONT_NO_15                  | yes, no cache to swap ->
SWAPFONT_CONT_17:
        BSR     SWAPFONT_FOUND                  | swap cache entry to active
SWAPFONT_NO_15:
        BSR     SWAPFONT_CONT_28                | full font lookup (FOND/FONT search)
| SWAPFONT_CONT_18: extract font metrics from strike into FMOutput
SWAPFONT_CONT_18:
        MOVE.L  (FOutFontHandle).w,A0           | A0 = font handle
        BSR     SWAPFONT_CONT_20                | dereference + ensure loaded
        TST.B   (FScaleDisable).w               | scaling disabled?
        BNE.B   SWAPFONT_OK_9                   | yes -> apply scaling
| no scaling: copy metrics directly from font strike
        LEA.L   (FOutAscent).w,A1               | A1 = output metrics
        MOVE.B  0x13(A0),(A1)+                  | ascent from strike header
        MOVE.B  0x15(A0),(A1)+                  | descent
        MOVE.B  0x7(A0),(A1)+                   | widMax
        MOVE.B  0x17(A0),(A1)                   | leading
SWAPFONT_CONT_19:
        BRA     SWAPFONT_CONT_2                 | -> apply style modifications

| ----------------------------------------------------------
|
| SWAPFONT_OK_9: scaled metrics - apply V/H scale factors to font metrics
|
SWAPFONT_OK_9:
        LEA.L   (FOutAscent).w,A1               | A1 = output metrics destination
        MOVE.B  0x13(A0),D0                     | D0 = ascent from strike
        BSR.B   SWAPFONT_CONT_21                | scale by vertical factor -> store
        MOVE.B  0x15(A0),D0                     | D0 = descent
        BSR.B   SWAPFONT_CONT_21                | scale by vertical factor -> store
        MOVE.B  0x7(A0),D0                      | D0 = widMax
        MOVE.L  (FScaleHFact).w,D1              | use horizontal scale for width
        BSR.B   SWAPFONT_CONT_22                | scale and store
        MOVE.B  0x17(A0),D0                     | D0 = leading
        BSR.B   SWAPFONT_CONT_21                | scale by vertical factor -> store
        BRA.B   SWAPFONT_CONT_19                | -> apply style modifications

| ----------------------------------------------------------
|
| SWAPFONT_CONT_20
|
| SWAPFONT_CONT_20: dereference font handle, loading from resource if purged
| A0 = font handle on entry, A0 = font data pointer on exit
| Called during boot (1,667 times in 30s trace).
SWAPFONT_CONT_20:
        TST.L   (A0)                            | master pointer nil (purged)?
        BNE.B   SWAPFONT_NO_16                  | no, still loaded ->
        MOVE.L  A0,-(SP)                        | push handle for LoadResource
        MOVE    #-0x1,(ROMMapInsert).w          | include ROM map in search
        _LoadResource                           | reload from resource fork
SWAPFONT_NO_16:
        MOVE.L  (A0),A0                         | dereference handle -> data pointer
        RTS                                     | return from SWAPFONT_CONT_20

| ----------------------------------------------------------
|
| SWAPFONT_CONT_21
|
| SWAPFONT_CONT_21: scale metric by vertical factor, round, store byte
| D0.B = metric value, A1 = output ptr (auto-incremented)
SWAPFONT_CONT_21:
        MOVE.L  (FScaleVFact).w,D1              | D1 = vertical scale factor
| SWAPFONT_CONT_22: scale D0.B by D1 (16.16 fixed), round, store to (A1)+
SWAPFONT_CONT_22:
        EXT     D0                              | sign-extend byte to word
        SWAP    D0                              | move to high word (integer part)
        CLR     D0                              | clear fractional part -> 16.16
        MOVEM.L D0-D1/A0-A1,-(SP)               | save for FixMul
        MOVE.L  D1,-(SP)                        | push scale factor
        BSR     SWAPFONT_CONT_24                | FixMul: metric * scale
        MOVEM.L (SP)+,D0/A0-A1                  | D0 = result, restore A0/A1
        ADDI.L  #0x8000,D0                      | round by adding 0.5
        SWAP    D0                              | integer part to low word
        MOVE.B  D0,(A1)+                        | store rounded byte result
        RTS                                     | return from SWAPFONT_CONT_21/SWAPFONT_CONT_22

| ----------------------------------------------------------
|
| SWAPFONT_CONT_23
|
| SWAPFONT_CONT_23: fixed-point constant 1.0 ($00010000) for scale factor comparison
SWAPFONT_CONT_23:
  .byte 0x00,0x01,0x00,0x00                     | 1.0 in 16.16 fixed point

| SWAPFONT_CONT_24: FixMul - multiply two 16.16 fixed-point values
| Pascal calling convention: pop D0 and D1 from stack, push result
| Optimizes identity (1.0) and integer cases to avoid full FixMul trap
| Called by: SWAPFONT_NO_7, SWAPFONT_NO_17, SWAPFONT_CONT_36, INVERTCOLOR_OK, SWAPFONT_CONT_8 (and 2 more)
SWAPFONT_CONT_24:
        MOVE.L  (SP)+,A1                        | pop return address
        MOVE.L  (SP)+,D0                        | pop first operand
        MOVE.L  (SP)+,D1                        | pop second operand
        MOVE.L  A1,-(SP)                        | push return address back
        MOVE.L  D0,-(SP)                        | push default result (D0)
        CMP.L   SWAPFONT_CONT_23(PC),D1         | D1 == 1.0?
        BEQ.B   SWAPFONT_EXIT_4                 | yes, result = D0 ->
        MOVE.L  D1,(SP)                         | push D1 as default result
        CMP.L   SWAPFONT_CONT_23(PC),D0         | D0 == 1.0?
        BEQ.B   SWAPFONT_EXIT_4                 | yes, result = D1 ->
        TST     D1                              | D1 integer part nonzero?
        BNE.B   SWAPFONT_OK_10                  | yes, need full FixMul ->
| fast path: D1 is pure fraction (0.xxxx), use MULU optimization
        SWAP    D1                              | D1.W = fraction part
        MOVE.L  D2,-(SP)                        | save D2
        MOVE.L  D0,D2                           | D2 = D0 (copy for hi*lo)
        SWAP    D2                              | D2.W = D0 integer part
        MULU    D1,D2                           | D2 = integer * fraction
        SWAP    D2                              | align to 16.16
        MULU    D1,D0                           | D0 = fraction * fraction
        ADD.L   D2,D0                           | combine partial products
        MOVE.L  (SP)+,D2                        | restore D2
        MOVE.L  D0,(SP)                         | store result on stack
        BRA.B   SWAPFONT_EXIT_4                 | -> return

| ----------------------------------------------------------
|
| SWAPFONT_OK_10: full FixMul via ROM trap (both operands have integer parts)
|
SWAPFONT_OK_10:
        MOVE.L  D1,-(SP)                        | push multiplicand
        MOVE.L  D0,-(SP)                        | push multiplier
        _FixMul                                 | result replaces top of stack
SWAPFONT_EXIT_4:
        MOVE.L  (SP)+,0x4(SP)                   | store result below return address
        RTS                                     | return from SWAPFONT_CONT_24 (FixMul)

| ----------------------------------------------------------
|
| SWAPFONT_CONT_25: FixRatio - compute fixed-point ratio D0/D1
| If D0 == D1, returns 1.0 (identity). Otherwise calls _FixRatio trap.
|
| Called during boot.
SWAPFONT_CONT_25:
        MOVE.L  (SP)+,A1                        | pop return address
        MOVE    (SP)+,D0                        | pop numerator
        MOVE    (SP)+,D1                        | pop denominator
        MOVE.L  A1,-(SP)                        | push return address back
        MOVE.L  SWAPFONT_CONT_23(PC),-(SP)      | push default: 1.0 ($00010000)
        CMP     D0,D1                           | numerator == denominator?
        BEQ.B   SWAPFONT_EXIT_4                 | yes, ratio = 1.0 ->
        MOVE    D1,-(SP)                        | push denominator for FixRatio
        MOVE    D0,-(SP)                        | push numerator
        _FixRatio                               | compute fixed-point ratio
        BRA.B   SWAPFONT_EXIT_4                 | -> store result and return

| ----------------------------------------------------------
|
| SWAPFONT_RETRY_2
|
| SWAPFONT_RETRY_2: load FONT resource by ID, searching ROM map too
| D3 = font resource ID (family<<7 | size) -> A0 = FONT handle (or nil)
SWAPFONT_RETRY_2:
        MOVE    #-0x1,(ROMMapInsert).w          | search ROM resource map
        BRA.B   SWAPFONT_CONT_27                | ->

| ----------------------------------------------------------
|
| SWAPFONT_CONT_26: load FONT resource, ROM map first (higher priority)
|
SWAPFONT_CONT_26:
        MOVE    #-0x100,(ROMMapInsert).w        | ROM map overrides app map
SWAPFONT_CONT_27:
        SUBQ.W  #0x4,SP                         | space for handle result
        MOVE.L  #0x464F4E54,-(SP)               | push 'FONT' resource type
        MOVE    D3,-(SP)                        | push font resource ID
        _GetResource                            | load the FONT resource
        ST.B    (GotStrike).w                   | flag: we have a font strike
        MOVE.L  (SP)+,D0                        | D0 = FONT handle (test for nil)
        MOVE.L  D0,A0                           | A0 = FONT handle
        RTS                                     | Z set if not found

| ----------------------------------------------------------
|
| SWAPFONT_CONT_28
|
| SWAPFONT_CONT_28: full font search - find FOND, then FONT resource for requested family/size
| A3 = FMInput record, sets FOutFontHandle and computes scale factors
| Called during boot.
SWAPFONT_CONT_28:
        CLR.B   (FontFlag).w                    | clear font search retry flag
        SUBA.L  A4,A4                           | A4 = nil (no FOND width subtable yet)
        BSR     SWAPFONT_CONT_10                | get effective font size -> D0
        MOVE    D0,D5                           | D5 = requested point size
        MOVE    (A3),D3                         | D3 = FMInput.family
SWAPFONT_CONT_29:
        BNE.B   SWAPFONT_CONT_30                | nonzero family ->
        MOVE    (SysFontFam).w,D3               | family 0 -> use system font family
SWAPFONT_CONT_30:
        CMPI    #0x1,D3                         | family 1 (application font)?
        BNE.B   SWAPFONT_NO_17                  | no ->
SWAPFONT_CONT_31:
        MOVE    (ApFontID).w,D3                 | substitute application font ID
SWAPFONT_NO_17:
| compute scaled point size: size * (deviceDPI/72) * (numer/denom)
        SUBA    #0xE,SP                         | stack space for FixMul chain
        MOVE    (FMDotsPerInch_v).w,-(SP)       | push device vertical DPI
        MOVE    #0x50,-(SP)                     | push 80 (screen reference DPI)
        BSR.B   SWAPFONT_CONT_25                | FixRatio(DPI, 80)
        SUBQ.W  #0x4,SP                         | space for second ratio
        MOVE    0xA(A3),-(SP)                   | push FMInput.numer.v
        MOVE    0xE(A3),-(SP)                   | push FMInput.denom.v
        BSR.B   SWAPFONT_CONT_25                | FixRatio(numer.v, denom.v)
        BSR     SWAPFONT_CONT_24                | FixMul: DPI ratio * numer/denom
        CLR     -(SP)                           | push 0 (high word of size)
        BSR     SWAPFONT_CONT_10                | get effective font size
        MOVE    D0,-(SP)                        | push size as fixed-point integer
        BSR     SWAPFONT_CONT_24                | FixMul: combined ratio * size
        MOVE    (SP)+,D0                        | D0 = scaled size (integer part)
        MOVE    (SP)+,D1                        | D1 = scaled size (fraction)
        BPL.B   SWAPFONT_CONT_32                | positive ->
        ADDQ.W  #0x1,D0                         | round negative up
SWAPFONT_CONT_32:
        MOVE    D0,(SP)                         | save scaled size on stack
| SWAPFONT_CONT_33: look up FOND resource for family D3
SWAPFONT_CONT_33:
        BSR     GETFNAME_CONT                   | look up FOND by family -> D0
        BNE     SWAPFONT_FOUND_7                | found FOND -> search its table
        CMPI    #0x200,D3                       | family < 512 (old-style FONT)?
        BCS.B   SWAPFONT_OK_11                  | yes -> try old FONT resource
        BRA     SWAPFONT_NO_25                  | no -> try FOND-based font lookup

| ----------------------------------------------------------
|
| SWAPFONT_CONT_34: try FONT resource with family in high bits, D0 as size
|
SWAPFONT_CONT_34:
        ANDI    #-0x80,D3                       | clear size bits, keep family
        OR      D0,D3                           | merge in new size
        BRA     SWAPFONT_RETRY_2                | -> load FONT resource

| ----------------------------------------------------------
|
| SWAPFONT_OK_11
|
| SWAPFONT_OK_11: no FOND found, try old-style FONT resource (family<<7 | size)
| Called during boot.
SWAPFONT_OK_11:
        MOVE    (SP)+,D0                        | D0 = scaled point size
        ANDI    #0x7F,D0                        | mask to 7 bits (FONT size field)
        ASL     #0x7,D3                         | shift family to FONT ID high bits
        OR      D0,D3                           | D3 = FONT resource ID
        MOVE    D0,D7                           | D7 = save requested size
        BSR     SWAPFONT_RETRY_2                | try exact size FONT resource
        BNE.B   SWAPFONT_FOUND_3                | found -> use it
| not found at exact size: try double and half sizes for scaling
        MOVE    D3,D4                           | D4 = save font ID
        MOVE    D7,D0                           | D0 = requested size
        CMPI    #0x40,D0                        | size >= 64?
        BGE.B   SWAPFONT_SKIP_6                 | yes, skip double (would overflow) ->
        ADD     D0,D0                           | try double size
        BSR.B   SWAPFONT_CONT_34                | look up FONT at 2x size
        BNE.B   SWAPFONT_FOUND_3                | found -> use (will scale down)
SWAPFONT_SKIP_6:
        MOVE    D7,D0                           | D0 = requested size
        LSR     #0x1,D0                         | try half size
        BCS.B   SWAPFONT_CONT_35                | odd size, can't halve evenly ->
        BSR.B   SWAPFONT_CONT_34                | look up FONT at half size
        BNE.B   SWAPFONT_FOUND_3                | found -> use (will scale up)
| SWAPFONT_CONT_35: exact/double/half not found - search adjacent sizes
SWAPFONT_CONT_35:
        MOVE    D4,D3                           | restore original font ID
        MOVEQ.L #0x1,D6                         | D6 = search step (+1)
        TST.B   (FScaleDisable).w               | scaling disabled?
        BEQ.B   SWAPFONT_NEXT_3                 | no -> search upward first
        MOVEQ.L #-0x1,D6                        | search downward first (prefer smaller)
SWAPFONT_NEXT_3:
        ADD     D6,D3                           | try next adjacent size
        ANDI    #0x7F,D3                        | mask size field
        BEQ     SWAPFONT_CONT_38                | wrapped to 0 -> exhausted search
        MOVE    D4,D0                           | D0 = original family bits
        ANDI    #-0x80,D0                       | keep family, clear size
        OR      D0,D3                           | combine family + new size
        BSR     SWAPFONT_RETRY_2                | try this FONT resource
        BEQ.B   SWAPFONT_NEXT_3                 | not found -> try next size
| SWAPFONT_FOUND_3: font resource found - compute scale factors
SWAPFONT_FOUND_3:
        MOVE.L  A0,(FOutFontHandle).w           | save font handle
        BSR     INVERTCOLOR_CONT_3              | build glyph bounding box table
        BSR     SWAPFONT_CONT_10                | get effective font size -> D0
| compute size ratio: requested size / actual size
        SUBQ.W  #0x4,SP                         | space for FixRatio result
        MOVE    D0,-(SP)                        | push requested size
        MOVE    D3,-(SP)                        | push actual FONT resource size
        ANDI    #0x7F,(SP)                      | mask to 7-bit size field
        BSR     SWAPFONT_CONT_25                | FixRatio(requested, actual)
        MOVE.L  (SP)+,D6                        | D6 = size ratio (16.16 fixed)
        MOVE.L  (WidthPtr).w,A0                 | width table
        MOVE    D3,0x42C(A0)                    | store FONT ID for width scaling
| compute horizontal and vertical scale factors
        MOVEQ.L #0x0,D5                         | D5 = 0 (horizontal first)
        BSR.B   SWAPFONT_CONT_36                | compute horizontal scale
        MOVEQ.L #0x2,D5                         | D5 = 2 (vertical)
| SWAPFONT_CONT_36: compute numer/denom scale factor for axis D5 (0=horiz, 2=vert)
SWAPFONT_CONT_36:
        SUBA    #0xC,SP                         | stack space for FixMul chain
        MOVE    0x8(A3,D5.W),-(SP)              | push FMInput.numer (h or v)
        MOVE    0xC(A3,D5.W),-(SP)              | push FMInput.denom (h or v)
        BSR     SWAPFONT_CONT_25                | FixRatio(numer, denom)
        SUBQ.W  #0x4,SP                         | space for DPI ratio
        LEA.L   (FMDotsPerInch_h).w,A0          | device DPI array
        MOVE    0x0(A0,D5.W),-(SP)              | push device DPI (h or v)
        MOVE    #0x50,-(SP)                     | push 80 (reference DPI)
        BSR     SWAPFONT_CONT_25                | FixRatio(DPI, 80)
        BSR     SWAPFONT_CONT_24                | FixMul: numer/denom * DPI/80
        MOVE.L  D6,-(SP)                        | push size ratio
        BSR     SWAPFONT_CONT_24                | FixMul: combined * size ratio
        LEA.L   (FOutNumer_h).w,A0              | output numer/denom array
        MOVE.L  (SP)+,D0                        | D0 = combined scale (16.16)
        LSR.L   #0x8,D0                         | convert to 8.8 for numer
        MOVE    D0,0x0(A0,D5.W)                 | store numer (h or v)
        MOVEQ.L #0x0,D1                         | clear D1
        MOVE    D0,D1                           | D1 = scale value (8.8)
        MOVE    #0x100,0x4(A0,D5.W)             | denom = 256 (1.0 in 8.8)
        TST.B   (FScaleDisable).w               | scaling enabled?
        BEQ.B   SWAPFONT_NO_20                  | no -> use 1:1 scale factor
| normalize numer/denom to range [0xC0..0x200) for best scaling precision
        MOVE    #0x100,D0                       | D0 = denom (starts at 256)
SWAPFONT_CONT_37:
        CMPI    #0x200,D1                       | numer >= 512?
        BLT.B   SWAPFONT_NO_18                  | no ->
        ASL     #0x1,D0                         | double denom
        ASR     #0x1,D1                         | halve numer
        BRA.B   SWAPFONT_CONT_37                | recheck

| ----------------------------------------------------------
|
| SWAPFONT_NO_18: normalize small numer values upward
|
SWAPFONT_NO_18:
        CMPI    #0xC0,D1                        | numer < 192?
        BGE.B   SWAPFONT_NO_19                  | no ->
        ASR     #0x1,D0                         | halve denom
        ASL     #0x1,D1                         | double numer
        BRA.B   SWAPFONT_NO_18                  | recheck

| ----------------------------------------------------------
|
| SWAPFONT_NO_19: fine adjust if numer in [192..256) using 3/4 interpolation
|
SWAPFONT_NO_19:
        CMPI    #0x100,D1                       | numer >= 256 (1.0)?
        BGE.B   SWAPFONT_OK_12                  | yes, well-normalized ->
        MOVE    D0,D2                           | D2 = denom
        ADD     D0,D0                           | D0 = 2*denom
        ADD     D2,D0                           | D0 = 3*denom
        ASR     #0x2,D0                         | D0 = 3*denom/4
        ASL     #0x2,D1                         | numer *= 4
        EXT.L   D1                              | sign-extend for DIVU
        DIVU    #0x3,D1                         | numer = 4*numer/3
        EXT.L   D1                              | clear remainder
SWAPFONT_OK_12:
        MOVE    D0,0x0(A0,D5.W)                 | store normalized numer
        ASL.L   #0x8,D1                         | convert to 16.16 fixed point
        TST     D5                              | horizontal axis?
        BEQ.B   SWAPFONT_OK_13                  | yes -> check vertical factor
        CMP.L   (FScaleHFact).w,D1              | H factor changed?
SWAPFONT_NO_20:
        BEQ.B   SWAPFONT_NO_21                  | no change ->
        MOVE.L  D1,(FScaleHFact).w              | update horizontal scale factor
        MOVE.L  (WidthTabHandle).w,A0           | get width table handle
        MOVE.L  (A0),A0                         | dereference width table handle
        CLR.L   0x400(A0)                       | invalidate cached font handle
        MOVEQ.L #-0x1,D2                        | -1 sentinel
        MOVE    D2,0x40C(A0)                    | invalidate cached FMInput family
        BRA.B   SWAPFONT_NO_21                  | -> store numer/denom in width table

| ----------------------------------------------------------
|
| SWAPFONT_OK_13: check if vertical scale factor changed
|
SWAPFONT_OK_13:
        CMP.L   (FScaleVFact).w,D1              | V factor changed?
        BEQ.B   SWAPFONT_NO_21                  | no ->
        MOVE.L  D1,(FScaleVFact).w              | update vertical scale factor
| SWAPFONT_NO_21: store normalized numer/denom in width table cache
SWAPFONT_NO_21:
        MOVE.L  (WidthPtr).w,A1                 | width table data
        LEA.L   0x424(A1),A1                    | A1 = cached numer/denom area
        MOVE    D0,0x0(A1,D5.W)                 | store numer (h or v)
        ASR.L   #0x8,D1                         | convert 16.16 back to 8.8
        MOVE    D1,0x4(A1,D5.W)                 | store denom (h or v)
        RTS                                     | return from SWAPFONT_CONT_36

| ----------------------------------------------------------
|
| SWAPFONT_CONT_38: adjacent size search exhausted (wrapped to 0)
| Decide whether to reverse search direction or try fallback
|
SWAPFONT_CONT_38:
        TST.B   (FScaleDisable).w               | scaling disabled?
        BEQ.B   SWAPFONT_NO_22                  | no ->
        NEG     D6                              | reverse search direction
        BMI.B   SWAPFONT_OK_15                  | was +1, now -1 -> try fallback
        BRA.B   SWAPFONT_OK_14                  | was -1, now +1 -> search other way

| ----------------------------------------------------------
|
| SWAPFONT_NO_22: scaling enabled, reverse direction check
|
SWAPFONT_NO_22:
        NEG     D6                              | reverse search direction
        BPL.B   SWAPFONT_OK_15                  | was -1, now +1 -> try fallback
SWAPFONT_OK_14:
        MOVE    D4,D3                           | restore original font ID
        BRA     SWAPFONT_NEXT_3                 | -> continue adjacent size search

| ----------------------------------------------------------
|
| SWAPFONT_OK_15: both directions exhausted - try alternate font family
|
SWAPFONT_OK_15:
        NOT.B   (FontFlag).w                    | toggle retry flag
        BNE     SWAPFONT_CONT_31                | first time -> try app font
        MOVEQ.L #0x0,D3                         | second time -> try system font
        BRA     SWAPFONT_CONT_29                | -> restart search with family 0

| ----------------------------------------------------------
|
| SWAPFONT_CONT_39
|
| SWAPFONT_CONT_39: query device driver for its DPI resolution
| D0 = device (0=screen, nonzero=printer driver refNum)
| Fills FMDotsPerInch_h/v with device resolution
SWAPFONT_CONT_39:
        TST     D0                              | screen device?
        BEQ.B   SWAPFONT_OK_16                  | yes -> use default DPI
        MOVEQ.L #-0x1,D0                        | init D0 for sign-extend
        MOVE.B  0x6(A3),D0                      | D0 = device driver refNum
        MOVEQ.L #0x32,D1                        | 50 bytes for param block
        SUBA.L  D1,SP                           | allocate param block on stack
        LEA.L   0x18(SP),A0                     | A0 = csParam area
        MOVE    D0,(A0)+                        | ioRefNum = driver refNum
        MOVE    #0x8,(A0)+                      | csCode = 8 (get resolution)
        LEA.L   (FMDotsPerInch_h).w,A1          | dest for DPI values
        MOVE.L  A1,(A0)+                        | csParam[0] = ptr to DPI buffer
        MOVE    0x6(A3),(A0)+                   | csParam[2] = device ID
        MOVE.L  A7,A0                           | A0 = param block
        _Status                                 | query driver for DPI
        ADDA.L  D1,SP                           | pop param block
        RTS                                     | return from SWAPFONT_CONT_39

| ----------------------------------------------------------
|
| SWAPFONT_OK_16
|
| Called during boot.
SWAPFONT_OK_16:
        LEA.L   (FMDotsPerInch_h).w,A1          | destination: Font Manager globals
        LEA.L   SWAPFONT_CONT_45(PC),A0         | source: default Font Manager parameters
        MOVEQ.L #0x1C,D0                        | length: 28 bytes
        _BlockMove                              | initialize Font Manager globals
        RTS                                     | return from SWAPFONT_OK_16

| ----------------------------------------------------------
|
| SWAPFONT_CONT_40
|
| SWAPFONT_CONT_40: search FOND font association table for size D3
| A2 = FOND handle; returns D0 = font resource handle (or 0 if not found)
SWAPFONT_CONT_40:
        MOVE.L  (A2),A0                         | dereference FOND handle
        LEA.L   0x34(A0),A0                     | A0 = font association table
        MOVE    (A0)+,D1                        | D1 = entry count - 1
SWAPFONT_LOOP_10:
        CMP     (A0)+,D3                        | compare size with table entry
        BEQ.B   SWAPFONT_FOUND_5                | exact match found ->
        BLT.B   SWAPFONT_FOUND_4                | requested < entry, not found ->
        ADDQ.W  #0x4,A0                         | skip style+resID fields
        DBF     D1,SWAPFONT_LOOP_10             | next entry
SWAPFONT_FOUND_4:
        MOVEQ.L #0x0,D0                         | return 0 (not found)
        RTS                                     | return from SWAPFONT_CONT_40

| ----------------------------------------------------------
|
| SWAPFONT_FOUND_5: found size in FOND association table - load font resource
|
SWAPFONT_FOUND_5:
        MOVE.L  (A0),D0                         | D0.hi = style, D0.lo = resource ID
        MOVE.L  D0,(FOutFontHandle).w           | save (style in high, ID in low)
| SWAPFONT_CONT_41: try loading NFNT resource first, fall back to FONT
SWAPFONT_CONT_41:
        MOVE.L  D0,-(SP)                        | save resource ID on stack
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x4E464E54,-(SP)               | push 'NFNT' resource type
        MOVE    D0,-(SP)                        | push resource ID
        MOVE    #-0x1,(ROMMapInsert).w          | include ROM map
        _GetResource                            | try loading NFNT
        MOVE.L  (SP)+,D0                        | D0 = NFNT handle
        BEQ.B   SWAPFONT_FOUND_6                | not found -> try FONT
        ADDQ.W  #0x4,SP                         | pop saved ID (not needed)
        RTS                                     | return with NFNT handle

| ----------------------------------------------------------
|
| SWAPFONT_FOUND_6: NFNT not found, try FONT resource with same ID
|
SWAPFONT_FOUND_6:
        MOVE.L  (SP),D0                         | D0 = saved resource ID
        MOVE.L  #0x464F4E54,-(SP)               | push 'FONT' resource type
        MOVE    D0,-(SP)                        | push resource ID
        MOVE    #-0x1,(ROMMapInsert).w          | include ROM map
        _GetResource                            | try loading FONT
        MOVE.L  (SP)+,D0                        | D0 = FONT handle (or nil)
        RTS                                     | return from SWAPFONT_FOUND_6 (FONT fallback)

| ----------------------------------------------------------
|
| SWAPFONT_FOUND_7
|
| SWAPFONT_FOUND_7: FOND found - search its font association table for requested size
SWAPFONT_FOUND_7:
        MOVE    (SP)+,D5                        | D5 = scaled point size
        MOVE.L  A2,-(SP)                        | save A2
        MOVE.L  D0,A2                           | A2 = FOND handle
        MOVE    D5,D3                           | D3 = size to search for
        BSR.B   SWAPFONT_CONT_40                | look up exact size in FOND
        BNE.B   SWAPFONT_FOUND_8                | found ->
| try double and half sizes for scaling
        TST.B   (FScaleDisable).w               | scaling disabled?
        BNE.B   SWAPFONT_SKIP_7                 | yes, skip size variants ->
        ADD     D3,D3                           | try double size
        BSR.B   SWAPFONT_CONT_40                | look up in FOND
        BNE.B   SWAPFONT_FOUND_8                | found ->
        MOVE    D5,D3                           | restore original size
        LSR     #0x1,D3                         | try half size
        BSR.B   SWAPFONT_CONT_40                | look up in FOND
SWAPFONT_FOUND_8:
        BNE.B   SWAPFONT_FOUND_10               | found -> style matching
| SWAPFONT_SKIP_7: no exact/double/half - find closest available size in FOND
SWAPFONT_SKIP_7:
        MOVE.L  (A2),A0                         | dereference FOND
        LEA.L   0x34(A0),A0                     | A0 = font association table
        MOVE    (A0)+,D4                        | D4 = entry count - 1
        MOVEQ.L #0x0,D1                         | D1 = best matching size (0=none)
        MOVEQ.L #0x7F,D2                        | D2 = smallest distance so far
SWAPFONT_LOOP_11:
        MOVE    D5,D0                           | D0 = requested size
        SUB     (A0),D0                         | D0 = delta (requested - available)
        BPL.B   SWAPFONT_CONT_42                | positive delta ->
        TST.B   (FScaleDisable).w               | scaling disabled?
        BEQ.B   SWAPFONT_NO_23                  | no ->
        TST     D1                              | already have a candidate?
        BNE.B   SWAPFONT_OK_17                  | yes, prefer smaller -> stop search
SWAPFONT_NO_23:
        NEG     D0                              | make delta positive
SWAPFONT_CONT_42:
        CMP     D2,D0                           | closer than best so far?
        BGT.B   SWAPFONT_NO_24                  | no ->
        MOVE    D0,D2                           | update best distance
        MOVE    (A0),D1                         | update best matching size
SWAPFONT_NO_24:
        ADDQ.W  #0x6,A0                         | next entry (6 bytes per entry)
        DBF     D4,SWAPFONT_LOOP_11             | loop all entries
SWAPFONT_OK_17:
        MOVE    D1,D3                           | D3 = best available size
        BSR     SWAPFONT_CONT_40                | look up in association table
        BNE.B   SWAPFONT_FOUND_10               | found -> style matching
| SWAPFONT_FOUND_9: FOND search failed - fall back to old-style FONT
SWAPFONT_FOUND_9:
        MOVE.L  (SP)+,A2                        | restore A2
        MOVE    D5,-(SP)                        | push size back on stack
        MOVE    (A3),D3                         | D3 = original family from FMInput
| SWAPFONT_NO_25: try family as old-style FONT ID (family < 512 only)
SWAPFONT_NO_25:
        CMPI    #0x1,D3                         | application font family?
        BNE.B   SWAPFONT_NO_26                  | no ->
        MOVE    (ApFontID).w,D3                 | substitute app font ID
SWAPFONT_OK_18:
        BRA     SWAPFONT_OK_11                  | -> try old-style FONT resource

| ----------------------------------------------------------
|
| SWAPFONT_NO_26: FOND family >= 16384 - enumerate FOND resources
|
SWAPFONT_NO_26:
        CMPI    #0x4000,D3                      | family < 16384?
        BCS.B   SWAPFONT_OK_18                  | yes -> try old FONT resource
        TST.B   (FontFlag).w                    | already tried enumeration?
        BNE.B   SWAPFONT_NEXT_5                 | yes -> next FOND ID
        ST.B    (FontFlag).w                    | set enumeration flag
        ANDI    #-0x200,D3                      | align to FOND block boundary
SWAPFONT_NEXT_4:
        BRA     SWAPFONT_CONT_33                | -> try this FOND ID

| ----------------------------------------------------------
|
| SWAPFONT_NEXT_5: enumerate FOND IDs within block, searching for one with fonts
|
SWAPFONT_NEXT_5:
        ADDQ.W  #0x1,D3                         | try next FOND ID
        MOVE    D3,D0                           | copy to check block boundary
        ANDI    #0x1FF,D0                       | within same 512-ID block?
        BNE.B   SWAPFONT_NEXT_4                 | yes -> try next
        CLR.B   (FontFlag).w                    | exhausted block, clear flag
        ADDQ.W  #0x2,SP                         | pop size from stack
        BRA     SWAPFONT_CONT_31                | -> fall back to app font

| ----------------------------------------------------------
|
| SWAPFONT_FOUND_10
|
| SWAPFONT_FOUND_10: find matching style variant at size D3 in FOND association table
SWAPFONT_FOUND_10:
        MOVE.L  (A2),A0                         | dereference FOND
        LEA.L   0x34(A0),A0                     | A0 = font association table
        MOVE    (A0)+,D1                        | D1 = entry count - 1
SWAPFONT_LOOP_12:
        CMP     (A0),D3                         | this entry matches size D3?
        BEQ.B   SWAPFONT_OK_20                  | yes -> check style
        ADDQ.W  #0x6,A0                         | skip to next entry
        DBF     D1,SWAPFONT_LOOP_12             | loop
        BRA.B   SWAPFONT_FOUND_9                | size not found -> fallback

| ----------------------------------------------------------
|
| SWAPFONT_OK_19: exact style match found - record position
|
SWAPFONT_OK_19:
        MOVE.L  A0,A1                           | A1 = matching entry (after style word)
        BRA.B   SWAPFONT_CONT_43                | -> load font from this entry

| ----------------------------------------------------------
|
| SWAPFONT_OK_20: found size in FOND - find best style match among duplicates
|
SWAPFONT_OK_20:
        ADDQ.W  #0x2,A0                         | skip past size field to style
        MOVEQ.L #0x0,D4                         | D4 = best style match score
        MOVE.B  0x4(A3),D2                      | D2 = requested style bits (face)
SWAPFONT_NEXT_6:
        MOVE    (A0)+,D6                        | D6 = this entry's style word
        CMP.B   D6,D2                           | exact style match?
        BEQ.B   SWAPFONT_OK_19                  | yes ->
| check if entry has styles we didn't request (extra styles = bad match)
        MOVE    D2,D7                           | D7 = requested styles
        NOT     D7                              | D7 = complement (styles NOT requested)
        AND.B   D6,D7                           | D7 = entry styles not in request
        BNE.B   SWAPFONT_SKIP_9                 | has extra styles -> skip this entry
| score: count how many requested styles this entry provides
        MOVEQ.L #0x0,D1                         | D1 = match score
        MOVEQ.L #0x7,D7                         | 8 style bits to check
SWAPFONT_LOOP_13:
        BTst    D7,D2                           | requested style bit set?
        BEQ.B   SWAPFONT_SKIP_8                 | no ->
        BTST    D7,D6                           | available style bit set?
        BEQ.B   SWAPFONT_SKIP_8                 | no -> skip adding score
        ADD.B   SWAPFONT_CONT_44(PC,D7.W),D1    | add weighted score for this style
SWAPFONT_SKIP_8:
        DBF     D7,SWAPFONT_LOOP_13             | next style bit
        CMP     D1,D4                           | better than best so far?
        BGE.B   SWAPFONT_SKIP_9                 | no ->
        MOVE    D1,D4                           | update best score
        MOVE.L  A0,A1                           | A1 = best matching entry
SWAPFONT_SKIP_9:
        ADDQ.W  #0x4,A0                         | skip resource ID, advance to next
        CMP     -0x2(A0),D3                     | still same size?
        BEQ.B   SWAPFONT_NEXT_6                 | yes -> check next style variant
| SWAPFONT_CONT_43: load font resource from best matching entry
SWAPFONT_CONT_43:
        MOVE    -0x2(A1),D6                     | D6 = style bits of matched entry
        MOVE    (FOutFontHandle_2).w,D1         | D1 = resource ID from earlier match
        CMP     (A1),D1                         | same resource ID?
        BEQ.B   SWAPFONT_OK_21                  | yes, already loaded ->
        MOVE.L  D0,-(SP)                        | save D0
        MOVE    (A1),D0                         | D0 = resource ID from FOND entry
        BSR     SWAPFONT_CONT_41                | load NFNT/FONT resource
        BNE.B   SWAPFONT_OK_22                  | loaded OK ->
        MOVE.L  (SP)+,D0                        | restore D0 (load failed)
        MOVE    (FOutFontHandle).w,D6           | use previously saved style
| SWAPFONT_OK_21: remove intrinsic styles, search FOND width subtable
SWAPFONT_OK_21:
        MOVE.L  D0,A0                           | A0 = font resource handle
        NOT     D6                              | complement: bits NOT provided by font
        AND.B   D6,(FOutUnused).w               | clear provided styles from request
        NOT     D6                              | restore original style bits
| search FOND for width subtable matching this style
        MOVE.L  (A2),A1                         | dereference FOND
        MOVEQ.L #0x0,D1                         | clear D1
        MOVE    0x6(A1),D1                      | D1 = FOND lastChar
        SUB     0x4(A1),D1                      | D1 = char range
        ADDQ.W  #0x3,D1                         | + missing + 2 entries
        ADD     D1,D1                           | * 2 bytes per entry = row size
        MOVE.L  0x10(A1),D0                     | D0 = offset to width subtable
        BEQ.B   SWAPFONT_NO_27                  | no width subtable ->
        ADDA.L  D0,A1                           | A1 = width subtable header
        MOVE    (A1)+,D2                        | D2 = number of style entries - 1
        BMI.B   SWAPFONT_NO_27                  | negative = no entries ->
SWAPFONT_LOOP_14:
        MOVE    (A1)+,D0                        | D0 = style word for this subtable
        CMP.B   D0,D6                           | matches font's intrinsic style?
        BEQ.B   SWAPFONT_OK_23                  | yes -> use this width subtable
        ADDA.L  D1,A1                           | skip width data (row size bytes)
        DBF     D2,SWAPFONT_LOOP_14             | next style entry
SWAPFONT_NO_27:
        MOVE.L  (SP)+,A2                        | restore A2
        BRA     SWAPFONT_FOUND_3                | -> finish with font metrics

| ----------------------------------------------------------
|
| SWAPFONT_OK_22: SWAPFONT_CONT_41 succeeded, discard saved D0
|
SWAPFONT_OK_22:
        ADDQ.W  #0x4,SP                         | discard saved D0
        BRA.B   SWAPFONT_OK_21                  | -> continue with loaded font

| ----------------------------------------------------------
|
| SWAPFONT_OK_23: found matching width subtable - save offset in A4
|
SWAPFONT_OK_23:
        SUBA.L  (A2),A1                         | A1 = offset from FOND start
        MOVE.L  A1,A4                           | A4 = width subtable offset for later
        BRA.B   SWAPFONT_NO_27                  | -> finish

| ----------------------------------------------------------
|
| SWAPFONT_CONT_44
|
| SWAPFONT_CONT_44: style match priority weights (indexed by style bit number)
| bold=4, italic=8, underline=1, outline=3, shadow=3, condense=2, extend=1
SWAPFONT_CONT_44:
  .byte 0x04,0x08,0x01,0x03,0x03,0x02           | bold=4,italic=8,uline=1,outline=3,shadow=3,condense=2
  .byte 0x01,0x00                               | extend=1, padding

| SWAPFONT_CONT_45: default FMOutput record + FMStyleTab + cursor data
| First 28 bytes: default DPI (80x80), style modification table, UL params
SWAPFONT_CONT_45:
  .byte 0x00,0x50,0x00,0x50,0x00,0x01           | DPI h=80, v=80; bold offset=1
  .byte 0x01,0x01,0x08,0x00,0x00,0x00           | bold extra=1,italic ofs=1,italic extra=8
  .byte 0x00,0x05,0x01,0x01,0x05,0x02           | outline ofs=0,outline ex=5,shadow=1,1,5,2
  .byte 0x02,0x00,0x00,0xFF,0x00,0x00           | condense=2,extend=0; UL ofs=0,FF,0,0
  .byte 0x01,0x01,0x01,0x01,0x00,0x77           | UL thick=1; cursor mask data row 1
  .byte 0x7A,0x3B,0xC9,0x35,0x30,0x19           | cursor mask data rows 2-3
  .byte 0x80,0xAF,0x30,0x18,0x7A,0x60           | cursor mask data rows 4-5
  .byte 0x18,0x09,0x00,0x60,0x31,0x98           | cursor mask data rows 6-7
  .byte 0x09,0x72,0x7B,0xBA,0x49,0xBF           | cursor mask data rows 8-9
  .byte 0xE0,0x9D,0x01,0x02,0x20,0xBF           | cursor mask data rows 10-11
  .byte 0x40,0x88,0x01,0xF1,0xFE,0x02           | cursor mask data rows 12-13
  .byte 0x0A,0x81,0xBC,0x04,0x07,0x03           | cursor data rows 14-15
  .byte 0x9A,0x08,0x04,0x0F,0x80,0x99           | cursor data rows 16-17
  .byte 0x1F,0xC0,0x37,0x60,0xB9,0x0F           | cursor data rows 18-19
  .byte 0x04,0x03,0xDF,0x0F,0x98,0x08           | cursor data rows 20-21
  .byte 0x37,0x60,0x1F,0xC1,0xA8,0x04           | cursor data rows 22-23
  .byte 0x0F,0x80,0x02,0x02,0x9A,0x01           | cursor data rows 24-25
  .byte 0x04,0x87,0x08,0x18                     | cursor data rows 26-27 (end)

| _GetFName ($A8FF): get font name from font number
| Pascal: procedure GetFName(familyID: INTEGER; VAR name: Str255);
GetFName:
        MOVE.L  D3,-(SP)                        | save D3
        MOVE    0xC(SP),D3                      | D3 = familyID from stack
| try FOND resource first
        MOVE    #-0x100,(ROMMapInsert).w        | include ROM resources
        BSR.B   GETFNAME_CONT_2                 | look up FOND by family ID
        BNE.B   GETFNAME_FOUND                  | found FOND ->
| no FOND: try old-style FONT resource
        CMPI    #0x200,D3                       | familyID >= 512?
        BCC.B   GETFNAME_FOUND_2                | yes, can't encode in old FONT ID ->
        ASL     #0x7,D3                         | convert to FONT resource ID
        BSR     SWAPFONT_CONT_26                | load FONT resource
        BEQ.B   GETFNAME_FOUND_2                | not found ->
| found font resource: get its name via GetResInfo
GETFNAME_FOUND:
        MOVE.L  D0,-(SP)                        | push resource handle
        PEA.L   (scratch8).w                    | push temp for resType
        MOVE.L  (SP),-(SP)                      | push temp for resID
        MOVE.L  0x14(SP),-(SP)                  | push name ptr (caller's VAR)
        MOVE    #-0x100,(ROMMapInsert).w        | include ROM
        _GetResInfo                             | get resource name -> caller's buffer
| clean up and return
GETFNAME_EXIT:
        MOVEQ.L #-0x1,D3                        | invalidate font caches
        MOVE    D3,(FONDID).w                   | invalidate FOND ID cache
        CLR.L   (LastFOND).w                    | clear last FOND handle
        MOVE.L  (SP)+,D3                        | restore D3
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x6,SP                         | strip Pascal params (4+2)
        JMP     (A0)                            | return

| ----------------------------------------------------------
|
| GETFNAME_FOUND_2
|
| GETFNAME_FOUND_2: font not found - return empty name string
GETFNAME_FOUND_2:
        MOVE.L  0x8(SP),A0                      | A0 = caller's name buffer
        CLR     (A0)                            | store empty string (length 0)
        BRA.B   GETFNAME_EXIT                   | -> clean up and return

| ----------------------------------------------------------
|
| GETFNAME_CONT
|
| GETFNAME_CONT: look up FOND resource by family ID with caching
| D3 = family ID, returns D0 = FOND handle (stripped), Z set if not found
| Called during boot.
GETFNAME_CONT:
        MOVE    #-0x1,(ROMMapInsert).w          | include ROM map in search
| GETFNAME_CONT_2: same but caller already set ROMMapInsert
GETFNAME_CONT_2:
        CMPI    #0x1,D3                         | application font family?
        BNE.B   GETFNAME_NO                     | no ->
        MOVE    (ApFontID).w,D3                 | substitute actual app font ID
GETFNAME_NO:
        CMP     (FONDID).w,D3                   | same as cached FOND?
        BEQ.B   GETFNAME_OK                     | yes, use cached ->
| load FOND resource for this family
        SUBQ.W  #0x4,SP                         | space for handle result
        MOVE.L  #0x464F4E44,-(SP)               | push 'FOND' resource type
        MOVE    D3,-(SP)                        | push family ID as resource ID
        _GetResource                            | load FOND resource
| restore purgeable flag on previous FOND before replacing cache
        MOVE.L  (LastFOND).w,D1                 | D1 = previous FOND handle+flags
        BEQ.B   GETFNAME_EMPTY                  | none ->
        MOVE.L  D1,A0                           | A0 = previous FOND master ptr
        MOVE.B  (LastFOND).w,(A0)               | restore original flags byte
GETFNAME_EMPTY:
        MOVE.L  (SP)+,D0                        | D0 = new FOND handle
        MOVE.L  D0,A0                           | A0 = FOND handle
        BEQ.B   GETFNAME_FOUND_3                | not found ->
| cache FOND: save flags byte in high byte of handle, mark non-purgeable
        MOVE.L  (A0),A0                         | dereference to get FOND data flags
        MOVE.B  (A0),(WidthListHand).w          | cache FOND flags for width list
        MOVE.L  D0,A0                           | A0 = handle again
        MOVE.B  (A0),D1                         | D1 = original master ptr flags
        BCLR    #0x6,(A0)                       | make non-purgeable while cached
        ROL.L   #0x8,D0                         | rotate flags byte to MSB
        MOVE.B  D1,D0                           | save original flags in high byte
        ROR.L   #0x8,D0                         | rotate back (flags saved in byte 3)
GETFNAME_FOUND_3:
        MOVE    D3,(FONDID).w                   | update FOND ID cache
        MOVE.L  D0,(LastFOND).w                 | update FOND handle cache
GETFNAME_OK:
        MOVE.L  (LastFOND).w,D0                 | D0 = cached FOND handle
        AND.L   (Lo3Bytes).w,D0                 | strip high byte (saved flags)
        RTS                                     | Z flag set if nil

| ----------------------------------------------------------
|
| _GetFNum ($A900)
|
| _GetFNum ($A900): get font number from font name
| Pascal: procedure GetFNum(fontName: Str255; VAR theNum: INTEGER);
GetFNum:
        LINK    A6,#-0x10E                      | local vars
        MOVE.L  D3,-(SP)                        | save D3
        ST.B    D3                              | D3 = true (found via FOND)
| try FOND resource first
        SUBQ.W  #0x4,SP                         | space for handle
        MOVE.L  #0x464F4E44,-(SP)               | 'FOND' resource type
        MOVE.L  0xC(A6),-(SP)                   | push font name
        MOVE    #-0x100,(ROMMapInsert).w        | include ROM
        _GetNamedResource                       | search by name
        MOVE.L  (SP)+,D0                        | D0 = FOND handle
        BNE.B   GETFNUM_FOUND                   | found ->
| no FOND: try old-style FONT resource
        MOVEQ.L #0x0,D3                         | D3 = false (old-style FONT)
        SUBQ.W  #0x4,SP                         | room for result handle
        MOVE.L  #0x464F4E54,-(SP)               | 'FONT' resource type
        MOVE.L  0xC(A6),-(SP)                   | push font name
        MOVE    #-0x100,(ROMMapInsert).w        | search ROM resource map too
        _GetNamedResource                       | look up FONT by name
        MOVE.L  (SP)+,D0                        | D0 = FONT handle (or NIL)
        BEQ.B   GETFNUM_FOUND_2                 | not found ->
| found font (FOND or FONT): get its resource ID via GetResInfo
GETFNUM_FOUND:
        MOVE.L  D0,-(SP)                        | push resource handle
        PEA.L   -0x4(A6)                        | push ptr for resID result
        PEA.L   -0x8(A6)                        | push ptr for resType result
        PEA.L   -0x10E(A6)                      | push ptr for resName result
        MOVE    #-0x100,(ROMMapInsert).w        | include ROM map
        _GetResInfo                             | get resource info -> locals
        MOVE.L  0x8(A6),A0                      | A0 = caller's VAR theNum
        MOVE    -0x4(A6),D0                     | D0 = resource ID
        TST.B   D3                              | found via FOND?
        BNE.B   GETFNUM_OK                      | yes, ID is family directly ->
        LSR     #0x7,D0                         | old FONT: extract family (ID >> 7)
GETFNUM_OK:
        MOVE    D0,(A0)                         | store font number in caller's VAR
GETFNUM_EXIT:
        MOVE.L  (SP)+,D3                        | restore D3
        UNLK    A6                              | tear down stack frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x8,SP                         | strip 8 bytes of Pascal params
        JMP     (A0)                            | return

| ----------------------------------------------------------
|
| GETFNUM_FOUND_2: font not found by name - return 0
|
GETFNUM_FOUND_2:
        MOVE.L  0x8(A6),A0                      | A0 = caller's VAR theNum
        CLR     (A0)                            | store 0 (not found)
        BRA.B   GETFNUM_EXIT                    | -> clean up and return

| ----------------------------------------------------------
|
| _SetFontLock ($A903)
|
| _SetFontLock ($A903): lock/unlock current font in memory
| Pascal: procedure SetFontLock(lockFlag: BOOLEAN);
SetFontLock:
        MOVE.L  (FOutFontHandle).w,A1           | A1 = current font handle
        TST.B   0x4(SP)                         | lock or unlock?
        BNE.B   SETFONTLOCK_CONT                | unlock ->
| lock: set purgeable bit to prevent purging
        BSET    #0x6,(A1)                       | make font purgeable (paradoxically)
        TST.L   (LastFOND).w                    | have a FOND too?
        BEQ.B   SETFONTLOCK_EXIT                | no ->
        BSET    #0x6,(LastFOND).w               | make FOND purgeable too
SETFONTLOCK_EXIT:
        MOVE.L  (SP)+,A0                        | pop return
        ADDQ.W  #0x2,SP                         | strip param
        JMP     (A0)                            | return
| unlock: reload if purged, clear purgeable bit
SETFONTLOCK_CONT:
        MOVE.L  A1,-(SP)                        | push font handle
        MOVE    #-0x1,(ROMMapInsert).w          | include ROM
        _LoadResource                           | ensure loaded
        BCLR    #0x6,(A1)                       | make non-purgeable
        BCLR    #0x6,(LastFOND).w               | FOND too
        BRA.B   SETFONTLOCK_EXIT                | -> return

| ----------------------------------------------------------
|
| _RealFont ($A902): check if font exists at exact size (no scaling)
| Pascal: function RealFont(fontNum: INTEGER; size: INTEGER): BOOLEAN;
|
RealFont:
        CLR     0x8(SP)                         | result = false initially
        MOVE.L  D3,-(SP)                        | save D3
        MOVE    0xA(SP),D3                      | D3 = font family
        BSR     GETFNAME_CONT                   | look for FOND resource
        BNE.B   REALFONT_FOUND                  | found FOND ->
| no FOND: try old-style FONT resource
        CMPI    #0x200,D3                       | family >= 512?
        BCC.B   REALFONT_EXIT_2                 | yes, can't be old-style ->
        ASL     #0x7,D3                         | build FONT resource ID
        MOVE    0x8(SP),D1                      | D1 = requested size
        ANDI    #0x7F,D1                        | mask to 7 bits
        BEQ.B   REALFONT_EXIT_2                 | if size 0, return false
        OR      D1,D3                           | D3 = FONT resource ID (family*128 + size)
        BSR     SWAPFONT_CONT_26                | try to load FONT resource
        BEQ.B   REALFONT_EXIT_2                 | not found -> return false
REALFONT_EXIT:
        ADDQ.B  #0x1,0xC(SP)                    | set result to true (1)
REALFONT_EXIT_2:
        MOVE.L  (SP)+,D3                        | restore D3
        MOVE.L  (SP)+,(SP)                      | strip return address, keep result?
        RTS                                     | return from RealFont

| ----------------------------------------------------------
|
| REALFONT_FOUND
|
REALFONT_FOUND:
        MOVE.L  D0,A0                           | A0 = FOND handle
        MOVE.L  (A0),A0                         | dereference FOND handle
        LEA.L   0x34(A0),A0                     | skip fixed FOND fields to get to association table
        MOVE    (A0)+,D2                        | D2 = number of entries - 1
        BMI.B   REALFONT_EXIT_2                 | if < 0, table is empty -> return false
        MOVE    0x8(SP),D1                      | D1 = requested size
REALFONT_LOOP:
        CMP     (A0),D1                         | compare with size in association table entry
        BEQ.B   REALFONT_EXIT                   | matched -> return true
        BLT.B   REALFONT_EXIT_2                 | requested size is smaller, list is sorted -> return false
        ADDQ.W  #0x6,A0                         | skip rest of entry (style and resource ID)
        DBF     D2,REALFONT_LOOP                | loop over entries
        BRA.B   REALFONT_EXIT_2                 | not found -> return false

| ----------------------------------------------------------
|
| Index2Color
|
| Index2Color: set FScaleDisable flag and invalidate font caches
| On Mac Plus (B&W), repurposed as SetFScaleDisable
Index2Color:
        MOVE.L  (SP)+,A0                        | pop return address
        MOVE.B  (SP)+,(FScaleDisable).w         | pop boolean -> FScaleDisable
        MOVE    #-0x1,(CurFMFamily).w           | invalidate cached family
        MOVE.L  A0,-(SP)                        | push return address back
        BSR     INITFONTS_CONT_2                | invalidate all width caches
        RTS                                     | return from SetFScaleDisable

| ----------------------------------------------------------
|
| Invert Color
|
| _FontMetrics ($A835): return detailed font metrics for current font
| Fills FMOutput record with scaled ascent, descent, widMax, leading
InvertColor:
        SUBQ.W  #0x2,SP                         | space for CharWidth result
        MOVE    #0x20,-(SP)                     | space character
        _CharWidth                              | force font swap if needed
        ADDQ.W  #0x2,SP                         | discard width
| copy font metrics from strike to output, applying scaling
        MOVEM.L A2-A3,-(SP)                     | save regs
        MOVE.L  0xC(SP),A2                      | A2 = output FontInfo ptr
        MOVE.L  (FOutFontHandle).w,A1           | current font handle
        MOVE.L  (A1),A1                         | dereference
        LEA.L   0x12(A1),A0                     | A0 = font strike metrics (owTLoc area)
        PEA.L   0x6(A1)                         | push font bounds rect
| scale 3 metric values (ascent, descent, leading)
        BSR.B   INVERTCOLOR_CONT                | scale and store metric 1 (ascent)
        BSR.B   INVERTCOLOR_CONT                | scale and store metric 2 (descent)
        BSR.B   INVERTCOLOR_CONT                | scale and store metric 3 (leading)
        MOVE.L  (SP)+,A0                        | A0 = font bounds rect
| scale widMax
        MOVE.L  (FScaleHFact).w,D1              | horizontal scale factor
        LEA.L   (FOutNumer_v).w,A1              | scaling numerator
        BSR.B   INVERTCOLOR_CONT_2              | scale widMax
        MOVE.L  (WidthTabHandle).w,(A2)         | store width table handle in output
| adjust metrics for shadow style
        MOVE.L  0xC(SP),A2                      | A2 = FontInfo ptr
        MOVEQ.L #0x0,D0                         | clear D0 for byte extend
        MOVE.B  (FOutShadow).w,D0               | shadow offset
        BEQ.B   INVERTCOLOR_NO                  | no shadow ->
        ADDQ.W  #0x1,(A2)                       | ascent += 1 (shadow extends up)
        ADD     D0,0x4(A2)                      | widMax += shadow offset
INVERTCOLOR_NO:
        MOVE.L  (WidthPtr).w,A0                 | width table data
        MOVE.L  0x408(A0),D0                    | D0 = spExtra from width table
        ADD.L   D0,0xC(A2)                      | add spExtra to leading in output
        MOVEM.L (SP)+,A2-A3                     | restore regs
        MOVE.L  (SP)+,(SP)                      | strip param (move ret addr down)
        RTS                                     | return from FontMetrics

| ----------------------------------------------------------
|
| INVERTCOLOR_CONT
|
| INVERTCOLOR_CONT: scale metric by vertical factor with numer/denom
INVERTCOLOR_CONT:
        MOVE.L  (FScaleVFact).w,D1              | D1 = vertical scale factor
        LEA.L   (FOutNumer_h).w,A1              | A1 = numer/denom for vertical
| INVERTCOLOR_CONT_2: scale metric at (A0)+ by D1, with numer/denom from A1
| Stores 16.16 fixed-point result at (A2)+
INVERTCOLOR_CONT_2:
        MOVE    (A0)+,D0                        | D0 = metric value from font
        MOVE.L  A0,-(SP)                        | save source pointer
        TST.B   (FScaleDisable).w               | scaling enabled?
        BNE.B   INVERTCOLOR_OK                  | yes -> use actual scale factor
        MOVE.L  SWAPFONT_CONT_23(PC),D1         | no -> force scale = 1.0
INVERTCOLOR_OK:
        SUBQ.W  #0x4,SP                         | space for FixMul chain result
        MOVE.L  D1,-(SP)                        | push scale factor
        SUBQ.W  #0x4,SP                         | space for metric as fixed
        CLR     -(SP)                           | push metric high word = 0
        MOVE    D0,-(SP)                        | push metric as integer
        SUBQ.W  #0x4,SP                         | space for numer/denom ratio
        MOVE    0x4(A1),-(SP)                   | push denom
        MOVE    (A1),-(SP)                      | push numer
        BSR     SWAPFONT_CONT_25                | FixRatio(numer, denom)
        BSR     SWAPFONT_CONT_24                | FixMul: metric * numer/denom
        BSR     SWAPFONT_CONT_24                | FixMul: result * scale factor
        MOVE.L  (SP)+,(A2)+                     | store 16.16 result in output
        MOVE.L  (SP)+,A0                        | restore source pointer
        RTS                                     | return from INVERTCOLOR_CONT/INVERTCOLOR_CONT_2

| ----------------------------------------------------------
|
| INVERTCOLOR_CONT_3
|
| INVERTCOLOR_CONT_3: build per-glyph bounding box table appended to font strike
| Scans bitmap to find top/bottom ink row for each glyph
| Used by QuickDraw for faster text clipping
| A0 = font handle
| Called during boot.
INVERTCOLOR_CONT_3:
        MOVEM.L D3-D7/A2-A4,-(SP)               | save regs
        MOVE.L  A0,A3                           | A3 = font handle
        MOVE.L  (A3),A1                         | A1 = font strike data
        MOVE    (A1)+,D0                        | D0 = fontType
        LSR     #0x1,D0                         | bit 0 = bbox table present?
        BCS.B   INVERTCOLOR_EXIT                | already built -> return
        MOVE    (A1)+,D0                        | D0 = firstChar
        MOVE    (A1),D5                         | D5 = lastChar
        SUB     D0,D5                           | D5 = char range
        ADDQ.W  #0x3,D5                         | + missing char + 2 extra entries
        ADD     D5,D5                           | * 2 bytes per bbox entry
        EXT.L   D5                              | sign-extend to long
| calculate new handle size with bbox data appended
        MOVE.L  (A3),A1                         | re-dereference (may have moved)
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE    0x10(A1),D0                     | D0 = rowWords
        ADDQ.L  #0x8,D0                         | + 8 header words
        ADD.L   D0,D0                           | * 2 = byte offset to bitmap end
        MOVE.L  D0,D1                           | D1 = offset to offset/width table
        SUB.L   D5,D1                           | D1 = (adjusted for table layout)
        ADD.L   D5,D0                           | D0 = past offset table
        MOVE.L  D0,D2                           | D2 = offset to bbox table
        ADD.L   D5,D0                           | D0 = new total size with bbox
        BTST    #0x1,0x1(A1)                    | font has 16-bit widths?
        BEQ.B   INVERTCOLOR_NO_2                | no ->
        ADD.L   D5,D0                           | add space for extra width table
        ADD.L   D5,D2                           | adjust bbox table offset
INVERTCOLOR_NO_2:
        _SetHandleSize                          | resize font handle
        BEQ.B   INVERTCOLOR_CONT_4              | success ->
INVERTCOLOR_EXIT:
        MOVEM.L (SP)+,D3-D7/A2-A4               | resize failed or already done
        RTS                                     | return from INVERTCOLOR_CONT_3

| ----------------------------------------------------------
|
| INVERTCOLOR_CONT_4
|
| INVERTCOLOR_CONT_4: resize succeeded - build bbox table by scanning bitmap
| Called during boot.
INVERTCOLOR_CONT_4:
        MOVE.L  (A3),A2                         | A2 = font strike data
        ORI     #0x1,(A2)                       | set bit 0 of fontType (bbox present)
        MOVE    0xE(A2),D3                      | D3 = fRectHeight (bitmap rows)
        ADDA.L  D1,A2                           | A2 = offset/width table
        MOVE.L  (A3),A4                         | A4 = font data base
        ADDA.L  D2,A4                           | A4 = bbox output table
        SUBQ.W  #0x2,D5                         | D5 = loop counter (entries - 1)
| INVERTCOLOR_NEXT: process each glyph - find top and bottom ink rows
INVERTCOLOR_NEXT:
        MOVE    #-0x100,(A4)                    | init bbox entry ($FF00 = no ink)
        MOVE    (A2)+,D7                        | D7 = glyph X start (bit offset)
        MOVE    (A2),D6                         | D6 = next glyph X start
        SUB     D7,D6                           | D6 = glyph pixel width
        BEQ     INVERTCOLOR_EMPTY               | zero width (space) ->
| INVERTCOLOR_NEXT_2: build bit mask for glyph columns, scan bitmap rows
INVERTCOLOR_NEXT_2:
        MOVE    D7,D2                           | D2 = bit position
        MOVE    D7,D0                           | D0 = bit position
        LSR     #0x4,D0                         | D0 = word index
        ADD     D0,D0                           | * 2 = byte offset
        MOVE.L  (A3),A1                         | re-dereference font handle
        ADDA    #0x1A,A1                        | A1 = bitmap data start (offset $1A)
        ADDA    D0,A1                           | A1 = column word in bitmap
        ANDI    #0xF,D2                         | D2 = bit position within word
        MOVE    D2,D1                           | D1 = bit position
        ADD     D1,D1                           | * 2 for word table index
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE    INVERTCOLOR_CONT_5(PC,D1.W),D0  | D0 = right-aligned bitmask
        SWAP    D0                              | move to high word (for long mask)
        MOVEQ.L #0x10,D1                        | D1 = 16 (bits per word)
        SUB     D2,D1                           | D1 = remaining bits in this word
        ADD     D1,D7                           | advance X past this word
        SUB     D1,D6                           | D6 = remaining glyph width
        BEQ.B   INVERTCOLOR_CONT_7              | fits in one word ->
        BPL.B   INVERTCOLOR_CONT_6              | spans multiple words ->
| glyph narrower than remaining bits - mask off right side
        MOVE    D6,D1                           | D1 = negative overshoot
        ADDI    #0x10,D1                        | adjust to positive
        ADD     D1,D1                           | * 2 for table index
        MOVE.L  INVERTCOLOR_CONT_5(PC,D1.W),D2  | D2 = right-side mask
        NOT.L   D2                              | invert (bits to clear)
        AND.L   D2,D0                           | narrow the column mask
        BRA.B   INVERTCOLOR_CONT_7              | -> scan with this mask

| ----------------------------------------------------------
|
| INVERTCOLOR_CONT_5
|
INVERTCOLOR_CONT_5:
  .byte 0xFF,0xFF,0x7F,0xFF,0x3F,0xFF           | bit masks: 16,15,14 bits from left
  .byte 0x1F,0xFF,0x0F,0xFF,0x07,0xFF           | bit masks: 13,12,11 bits from left
  .byte 0x03,0xFF,0x01,0xFF,0x00,0xFF           | bit masks: 10,9,8 bits from left
  .byte 0x00,0x7F,0x00,0x3F,0x00,0x1F           | bit masks: 7,6,5 bits from left
  .byte 0x00,0x0F,0x00,0x07,0x00,0x03           | bit masks: 4,3,2 bits from left
  .byte 0x00,0x01,0x00,0x00                     | bit masks: 1,0 bits from left
| INVERTCOLOR_CONT_6: glyph spans next word - extend mask for right portion
INVERTCOLOR_CONT_6:
        MOVEQ.L #0x10,D4                        | 16 bits per word
        MOVE    D6,D1                           | D1 = remaining glyph width
        CMP     D4,D1                           | more than 16 remaining?
        BLE.B   INVERTCOLOR_NO_3                | no ->
        MOVE    D4,D1                           | clamp to 16
INVERTCOLOR_NO_3:
        ADD     D1,D1                           | * 2 for table index
        MOVE    INVERTCOLOR_CONT_5(PC,D1.W),D2  | D2 = mask for right-side bits
        NOT     D2                              | invert to get bits to set
        OR      D2,D0                           | extend column mask rightward
        SUB     D4,D6                           | reduce remaining width
        ADD     D4,D7                           | advance X position
| INVERTCOLOR_CONT_7: scan bitmap rows from top, looking for first ink row
INVERTCOLOR_CONT_7:
        MOVE.L  A1,-(SP)                        | save bitmap column pointer
        MOVE    D3,D1                           | D1 = fRectHeight (row count)
        SUBQ.W  #0x1,D1                         | adjust for DBF
        MOVEQ.L #0x0,D4                         | D4 = current row (top -> down)
        MOVE.L  (A3),A0                         | re-dereference font handle
        MOVE    0x18(A0),A0                     | A0 = rowWords (words per row)
        ADDA    A0,A0                           | A0 = rowBytes (bytes per row)
INVERTCOLOR_LOOP:
        MOVE.L  (A1),D2                         | D2 = bitmap data at this row
        AND.L   D0,D2                           | mask to glyph columns
        BNE.B   INVERTCOLOR_FOUND               | ink found -> record top row
        ADDQ.W  #0x1,D4                         | next row
        ADDA    A0,A1                           | advance to next bitmap row
        DBF     D1,INVERTCOLOR_LOOP             | loop all rows
        ADDQ.L  #0x4,SP                         | discard saved pointer (no ink found)
        MOVEQ.L #0x0,D6                         | D6 = 0 (no more columns to check)
INVERTCOLOR_EMPTY:
        CLR     (A4)+                           | store 0 in bbox (empty glyph)
        BRA.B   INVERTCOLOR_NEXT_3              | -> next glyph

| ----------------------------------------------------------
|
| INVERTCOLOR_FOUND: found top ink row - record it, then scan from bottom for last row
|
| Called during boot.
INVERTCOLOR_FOUND:
        CMP.B   (A4),D4                         | top row < current min?
        BCC     INVERTCOLOR_NO_4                | no ->
        MOVE.B  D4,(A4)                         | update top row (min ascent)
| INVERTCOLOR_NO_4: scan bitmap rows from bottom up for last ink row
INVERTCOLOR_NO_4:
        MOVE.L  (SP)+,A1                        | restore bitmap column pointer
        MOVE    D3,D2                           | D2 = fRectHeight
        SUBQ.W  #0x1,D2                         | D2 = last row index
        MOVE    A0,D4                           | D4 = rowBytes
        MULU    D4,D2                           | D2 = byte offset to last row
        ADDA.L  D2,A1                           | A1 = last row of this column
        MOVE    D3,D4                           | D4 = fRectHeight (bottom row + 1)
        MOVE    D3,D1                           | D1 = loop counter
        SUBQ.W  #0x1,D1                         | adjust for DBF
INVERTCOLOR_LOOP_2:
        MOVE.L  (A1),D2                         | D2 = bitmap data at this row
        AND.L   D0,D2                           | mask to glyph columns
        BNE.B   INVERTCOLOR_FOUND_2             | ink found -> record bottom row
        SUBQ.W  #0x1,D4                         | move up one row
        SUBA    A0,A1                           | back up one row
        DBF     D1,INVERTCOLOR_LOOP_2           | loop all rows
        BRA.B   INVERTCOLOR_EMPTY               | empty glyph -> move to next glyph

| ----------------------------------------------------------
|
| INVERTCOLOR_FOUND_2
|
| INVERTCOLOR_FOUND_2: compute glyph height (bottom - top) and update max
| Called during boot.
INVERTCOLOR_FOUND_2:
        SUB.B   (A4)+,D4                        | D4 = bottom - top = glyph ink height
        CMP.B   (A4)+,D4                        | greater than current max height?
        BLE.B   INVERTCOLOR_NEXT_3              | no ->
        MOVE.B  D4,-0x1(A4)                     | update max height in bbox entry
INVERTCOLOR_NEXT_3:
        SUBQ.L  #0x2,A4                         | back up to current bbox entry
        TST     D6                              | more column words for this glyph?
        BGT     INVERTCOLOR_NEXT_2              | yes -> scan next word column
        ADDQ.L  #0x2,A4                         | advance to next glyph's bbox
        SUBQ.W  #0x2,D5                         | decrement glyph counter
        BGT     INVERTCOLOR_NEXT                | more glyphs -> process next
        BRA     INVERTCOLOR_EXIT                | done -> restore regs and return

