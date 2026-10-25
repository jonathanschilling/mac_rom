| Font Manager
|
| Apple source: FontMgr.a (MacSEROM.lst module FONTMANAGER). InitFonts
| ($A8FE: FMOutput and default cursor data into low memory, ROM font 0,
| JSwapFont), the font search and strike loading behind _FMSwapFont
| (SwapFont: FMInput -> FMOutput, FMStyleTab style adjustments,
| 'FONT' resources, CurFMFamily/CurFMFace/CurFMSize/CurFMNeedBits),
| GetFName ($A8FF), GetFNum ($A900), SetFontLock ($A903) and RealFont
| ($A902). The QuickDraw glue in front of it (cursor and screen
| J-vector trampolines, _FMSwapFont's vector jump) is in
| quickdraw/QuickGlue.s.
|
| References:
| Inside Macintosh Vol I, Ch 7: The Font Manager

| ----------------------------------------------------------
| _InitFonts ($A8FE): initialize the Font Manager
|
| Classic version is much simpler than Plus's InitFonts: no
| WidthTabHandle, no FMSwapFont/SwapFont alias check, no fractional
| width disable. Just installs FMOutput defaults, clears device,
| loads ROM font 0, and installs SwapFont as JSwapFont.
| Called during boot.
InitFonts:
        MOVE.L  D3,-(SP)                        | save D3
        MOVEQ.L #-0x1,D0                        | D0 = -1 (invalid sentinel)
        MOVE    D0,(CurFMFamily).w              | invalidate cached font family
        BSR.W   FM_INSTALL_DEFAULTS             | install FMOutput + cursor defaults
        CLR     (CurFMDevice).w                 | current device = screen
        CLR.B   (FScaleDisable).w               | enable font scaling
        MOVE    (SPFont).w,(ApFontID).w         | application font from PRAM
        MOVEQ.L #0xC,D3                         | 12 = default size
        MOVE    D3,(GotStrike).w                | default font strike size
        BSR.W   SWAPFONT_CONT_27                | load ROM font 0
        MOVE.L  A0,(ROMFont0).w                 | save system font handle
        MOVE.L  (SP)+,D3                        | restore D3
        LEA     SwapFont(PC),A0                 | A0 = SwapFont entry point
        MOVE.L  A0,(JSwapFont).w                | install SwapFont vector
        RTS                                     | return from InitFonts
SWAPFONT_RETRY:
        TST.B   5(A3)                           | FMInput.needBits low byte
        BEQ.B   SWAPFONT_CONT                   | zero -> tolerate face mismatch, keep checking
SWAPFONT_OK:
        BRA.W   FM_SWAPFONT_MID                 | cache miss -> slow path: load new font
SwapFont:
        LEA.L     (FOutError).w,A0              | A0 = FMOutput record base (FOutError is +0)
        MOVE.L  A0,8(SP)                        | D4 = extra width addend
        MOVE.L  A3,-(SP)                        | save A3 across call
        MOVE.L  8(SP),A3                        | A3 = FMInput pointer from caller
        CLR     (FOutError).w                   | clear FOutError before lookup
        MOVE.L  A3,A0                           | A0 walks FMInput record
        LEA.L     (CurFMFamily).w,A1            | A1 walks cached FMInput state
        CMPM.L  (A0)+,(A1)+                     | family+size match cache?
        BNE.B   SWAPFONT_OK                     | no -> cache miss
        MOVE.B  (A0)+,D0                        | D0 = requested face byte
        MOVE.B  (A1)+,D1                        | D1 = cached face byte
        CMPM.B  (A0)+,(A1)+                     | NeedBits flag match?
        BNE.B   SWAPFONT_RETRY                  | no -> handle NeedBits divergence
SWAPFONT_CONT:
        CMPM.W  (A0)+,(A1)+                     | device id match?
        BNE.B   SWAPFONT_OK                     | no -> cache miss
        CMPM.L  (A0)+,(A1)+                     | numer.v + numer.h match?
        BNE.B   SWAPFONT_OK                     | no -> cache miss
        CMPM.L  (A0)+,(A1)+                     | denom.v + denom.h match?
        BNE.B   SWAPFONT_OK                     | no -> cache miss
        CMP.B   D1,D0                           | face bytes equal?
        BNE.B   FM_SAVEREGS_TAIL                | no -> face changed, reapply style
| ----------------------------------------------------------
| FM_LOADFONTRES
| Called during boot.
FM_LOADFONTRES:
        MOVE.L  (FOutFontHandle).w,A0           | A0 = current font handle
        TST.L   (A0)                            | master pointer non-nil?
        BNE.B   FM_EPILOGUE                     | yes -> font already loaded
        MOVE.L  A0,-(SP)                        | push handle for trap
        _LoadResource                           | reload purged font strike

        TST     (ResErr).w                      | reload succeeded?
        BEQ.B   FM_EPILOGUE                     | yes -> done
        MOVE.L  (ROMFont0).w,(FOutFontHandle).w | fall back to ROM system font (Chicago 12)
FM_EPILOGUE:
        MOVE.L  (SP)+,A3                        | restore A3
        MOVE.L  (SP)+,(SP)                      | strip FMInput pointer param
        RTS                                     | return from FM_EPILOGUE
FM_SAVEREGS_TAIL:
        MOVEM.L D3-D7,-(SP)                     | save D3-D7 across slow path
FM_APPLY_STYLE:
        LEA.L     (FOutBold).w,A0               | A0 = FMOutput style fields
        CLR.L   (A0)+                           | clear bold + italic offsets
        CLR     (A0)+                           | clear ULOffset + ULShadow
        CLR.B   (A0)+                           | clear ULThick byte
        MOVE.B  4(A3),D1                        | D1 = FMInput.face style bits
        BEQ.B   FM_SWAPFONT_NOCTL               | plain text -> skip style table
        MOVEQ.L #0x0,D2                         | D2 = field offset accumulator
        LEA.L     (FMStyleTab).w,A1             | A1 = global style modifier table
        MOVEQ.L #0x6,D0                         | 7 style entries (DBF counts to -1)
        LEA.L     (FOutBold).w,A0               | A0 = FMOutput style fields base
SWAPFONT_LOOP:
        MOVE.B  (A1)+,D2                        | D2 = FMOutput field offset
        MOVE.B  (A1)+,D3                        | D3 = addend for style field
        MOVE.B  (A1)+,D4                        | D4 = extra-width addend
        LSR     #0x1,D1                         | shift out lowest face bit
        BCC.B   SWAPFONT_SKIP                   | bit 0 -> style not requested
        ADD.B   D3,0(A0,D2.W)                   | 0(A0,D2.W) += D3
        ADD.B   D4,(FOutExtra).w                | (FOutExtra).w += D4
SWAPFONT_SKIP:
        DBRA    D0,SWAPFONT_LOOP                | next style entry
        BTST    #0x2,4(A3)                      | FMInput.face underline bit set?
        BEQ.B   FM_SWAPFONT_NOCTL               | no -> skip UL fields
        LEA.L     (FOutULOffset).w,A0           | A0 = FMOutput UL fields
        MOVE.B  (A1)+,(A0)+                     | copy UL offset from style table
        MOVE.B  (A1)+,(A0)+                     | copy UL shadow
        MOVE.B  (A1)+,(A0)+                     | copy UL thickness
FM_SWAPFONT_NOCTL:
        MOVEQ.L #-0x1,D0                        | prime D0 sign-extension
        MOVE.B  6(A3),D0                        | D0 = FMInput.device byte
        BEQ.B   FM_COPY_INPUT                   | device 0 (screen) -> skip _Control call
        MOVEQ.L #0x32,D1                        | D1 = sizeof(IOParam) = 50
        SUBA.L  D1,SP                           | SP -= D1
        MOVE.L  SP,A0                           | A0 = IOParam on stack
        MOVE    D0,24(A0)                       | ioRefNum = device id
        MOVE    #0x8,26(A0)                     | csCode 8 = SetUpFontMetrics
        MOVE.L  A3,28(A0)                       | csParam = FMInput pointer
        MOVE    6(A3),0x20(A0)                  | ioVRefNum = device id
        _Control                                | ask printer driver for metrics
        ADDA.L  D1,SP                           | SP += D1 (unwind IOParam)
FM_COPY_INPUT:
        MOVE.L  A3,A0                           | A0 = FMInput source
        LEA.L     (CurFMFamily).w,A1            | A1 = cached FMInput dest
        MOVE.L  (A0)+,(A1)+                     | copy family + size
        MOVE.L  (A0)+,(A1)+                     | copy face + needBits
        MOVE.L  (A0)+,(A1)+                     | copy device + numer.v
        MOVE.L  (A0)+,(A1)+                     | copy numer.h + denom.v
        MOVE.B  (GotStrike).w,(CurFMNeedBits).w | propagate GotStrike flag to CurFMNeedBits
        MOVEM.L (SP)+,D3-D7                     | restore D3-D7
        BRA.W   FM_LOADFONTRES                  | ensure font handle valid -> exit
FM_SWAPFONT_MID:
        MOVEM.L D3-D7,-(SP)                     | save D3-D7 across slow path
        MOVE    6(A3),D0                        | D0 = FMInput.device
        CMP     (CurFMDevice).w,D0              | same device as cached?
        BEQ.B   FM_LOAD_METRICS                 | yes -> reuse cached DPI
        BSR.W   SWAPFONT_CONT_39                | query device driver for DPI
FM_LOAD_METRICS:
        BSR.B   SWAPFONT_CONT_27_CONT_3         | compute scaling, find best FONT
        MOVE.L  (FOutFontHandle).w,A0           | A0 = chosen font handle
        MOVE.L  A0,-(SP)                        | push handle for trap
        _LoadResource                           | ensure strike data is in memory
        MOVE.L  (A0),A0                         | A0 = font strike pointer
        LEA.L     (FOutAscent).w,A1             | A1 = FMOutput metric fields
        MOVE.B  19(A0),(A1)+                    | ascent = FRec.ascent
        MOVE.B  21(A0),(A1)+                    | descent = FRec.descent
        MOVE.B  7(A0),(A1)+                     | widMax = FRec.widMax
        MOVE.B  23(A0),(A1)                     | leading = FRec.leading
        BRA.W   FM_APPLY_STYLE                  | now apply face style adjustments
FM_GET_SIZE:
        MOVE    2(A3),D5                        | D5 = FMInput.size
        BNE.B   FM_GET_SIZE_RTS                 | nonzero -> use it
        MOVE.B  (FMDefaultSize).w,D5            | zero -> substitute system default size
FM_GET_SIZE_RTS:
        RTS                                     | return D5 = effective size
FM_FINDFONT:
        TST.B   5(A3)                           | FMInput.needBits flag set?
        BNE.B   SWAPFONT_CONT_27                | yes -> need bitmap, skip FOND probe
        SUBQ.W  #0x4,SP                         | reserve handle slot on stack
        CLR.B   (GotStrike).w                   | assume FOND match (no strike)
        MOVE.L  #0x46574944,-(SP)               | push 'FWID' (font width) restype
        MOVE    D3,-(SP)                        | push res ID (family<<7|size)
        _GetResource                            | try fractional-width FOND
        MOVE.L  (SP)+,D0                        | D0 = handle (or nil)
        BNE.B   SWAPFONT_CONT_27_CONT           | found FWID -> done
SWAPFONT_CONT_27:
        SUBQ.W  #0x4,SP                         | reserve handle slot on stack
        MOVE.L  #0x464F4E54,-(SP)               | push 32-bit immediate 'FONT'
        MOVE    D3,-(SP)                        | push res ID (family<<7|size)
        _GetResource                            | load FONT bitmap strike
        ST      (GotStrike).w                   | (GotStrike).w := -1 (true)
        MOVE.L  (SP)+,D0                        | D0 = strike handle (or nil)
SWAPFONT_CONT_27_CONT:
        MOVE.L  D0,A0                           | A0 = handle, sets Z if nil
        RTS                                     | return with handle in A0
SWAPFONT_CONT_27_CONT_2:
        ANDI    #-0x80,D3                       | clear size bits in D3
        OR      D0,D3                           | merge new size into res ID
        RTS                                     | return updated D3
SWAPFONT_CONT_27_CONT_3:
        BSR.B   FM_GET_SIZE                     | D5 = effective size
        MOVE    (A3),D3                         | D3 = FMInput.family
        CMPI    #0x1,D3                         | application font marker?
        BNE.B   SWAPFONT_CONT_27_NO             | no -> use family as-is
SWAPFONT_CONT_27_CONT_4:
        MOVE    (ApFontID).w,D3                 | yes -> substitute ApFontID
SWAPFONT_CONT_27_NO:
        SUBA.W  #0xE,SP                         | SP -= #0xE
        MOVE    (FMDotsPerInch_v).w,-(SP)       | push device vertical DPI
        MOVE    #0x50,-(SP)                     | push 80 (screen DPI numerator)
        _FixRatio                               | compute device/screen DPI ratio
        SUBQ.W  #0x4,SP                         | reserve Fixed result slot
        MOVE    10(A3),-(SP)                    | push FMInput.numer.v
        MOVE    14(A3),-(SP)                    | push FMInput.denom.v
        _FixRatio                               | compute caller's vertical scale
        _FixMul                                 | multiply DPI ratio by caller scale
        CLR     -(SP)                           | clear high word of size operand
        MOVE    2(A3),-(SP)                     | push FMInput.size as low word
        BNE.B   SWAPFONT_CONT_27_NO_2           | size nonzero -> proceed
        MOVE.B  (FMDefaultSize).w,1(SP)         | zero -> patch in default size
SWAPFONT_CONT_27_NO_2:
        _FixMul                                 | scale by requested point size
        .short  0xA86C                          | A-line trap $A86C
        MOVE    (SP)+,D0                        | D0 = scaled effective size
        ANDI    #0x7F,D0                        | clamp to 7-bit FONT-id range
        ASL     #0x7,D3                         | shift family up to FONT-id high bits
        OR      D0,D3                           | D3 = family<<7 | size = FONT res ID
        MOVE    D0,D7                           | D7 = preferred size (saved)
        BSR.W   FM_FINDFONT                     | try exact-size resource
        BNE.B   SWAPFONT_CONT_27_CONT_8         | found -> done
        MOVE    D3,D4                           | D4 = base FONT id (family<<7)
        MOVE    D7,D0                           | D0 = preferred size
        CMPI    #0x40,D0                        | size >= 64?
        BGE.B   SWAPFONT_CONT_27_CONT_5         | yes -> skip 2x doubling step
        ADD     D0,D0                           | try 2x size (scaled-up bitmap)
        BSR.B   SWAPFONT_CONT_27_CONT_2         | rebuild res ID with new size
        BSR.W   FM_FINDFONT                     | look up doubled-size font
        BNE.B    SWAPFONT_CONT_27_CONT_8        | found -> done
SWAPFONT_CONT_27_CONT_5:
        MOVE    D7,D0                           | D0 = preferred size
        LSR     #0x1,D0                         | try half size (scaled-down)
        BCS.B   SWAPFONT_CONT_27_CONT_6         | odd -> can't halve cleanly
        BSR.B   SWAPFONT_CONT_27_CONT_2         | rebuild res ID with halved size
        BSR.W   FM_FINDFONT                     | look up half-size font
        BNE.B   SWAPFONT_CONT_27_CONT_8         | found -> done
SWAPFONT_CONT_27_CONT_6:
        MOVE    D4,D3                           | restore base id (family<<7)
        MOVEQ.L #0x1,D6                         | D6 = +1 step (search up first)
SWAPFONT_CONT_27_CONT_7:
        ADD     D6,D3                           | advance size by step
        ANDI    #0x7F,D3                        | isolate size bits
        BEQ.B   SWAPFONT_CONT_27_CONT_11        | yes -> use default DPI
        MOVE    D4,D0                           | reload base id
        ANDI    #-0x80,D0                       | keep only family bits
        OR      D0,D3                           | rebuild res ID with new size
        BSR.W   FM_FINDFONT                     | probe nearby size
        BEQ.B   SWAPFONT_CONT_27_CONT_7         | not found -> next step
SWAPFONT_CONT_27_CONT_8:
        MOVE.L  A0,(FOutFontHandle).w           | ioRefNum = driver refNum
        BSR.W   FM_GET_SIZE                     | D5 = effective size
        SUBQ.W  #0x4,SP                         | reserve Fixed result slot
        MOVE    D5,-(SP)                        | csParam[0] = ptr to DPI buffer
        MOVE    D3,-(SP)                        | csParam[2] = device ID
        ANDI    #0x7F,(SP)                      | (SP) &= 0x7F
        _FixRatio                               | FixRatio(reqSize, foundSize)
        MOVE.L  (SP)+,D6                        | D6 = font/requested ratio
        MOVEQ.L #0x0,D5                         | D5 = vertical-axis offset
        BSR.B   SWAPFONT_CONT_27_CONT_9         | compute vertical FOutNumer/Denom
        MOVEQ.L #0x2,D5                         | D5 = horizontal-axis offset
SWAPFONT_CONT_27_CONT_9:
        SUBA.W  #0xC,SP                         | SP -= #0xC
        MOVE    8(A3,D5.W),-(SP)                | push FMInput.numer[axis]
        MOVE    0xC(A3,D5.W),-(SP)              | push FMInput.denom[axis]
        _FixRatio                               | caller-requested scale ratio
        SUBQ.W  #0x4,SP                         | reserve Fixed result slot
        LEA.L     (FMDotsPerInch_h).w,A0        | A0 = device DPI table
        MOVE    0(A0,D5.W),-(SP)                | push device DPI[axis]
        MOVE    #0x50,-(SP)                     | push 80 (screen DPI denom)
        _FixRatio                               | device/screen DPI ratio
        _FixMul                                 | multiply scale * dpi ratio
        MOVE.L  D6,-(SP)                        | push size ratio for second mul
        _FixMul                                 | final scale = size * dpi * caller
        LEA.L     (FOutNumer_h).w,A0            | A0 = FMOutput numer/denom table
        MOVE.L  (SP)+,D0                        | D0 = combined scale (Fixed)
        LSR.L   #0x8,D0                         | shift Fixed -> 16.0 numerator
        ADDQ.W  #0x8,D0                         | round to nearest 1/16
        ANDI    #-0x10,D0                       | quantize to multiple of 16
        MOVE    D0,0(A0,D5.W)                   | FOutNumer[axis] = scaled value
        MOVE    #0x100,4(A0,D5.W)               | FOutDenom[axis] = 256
        TST.B   (FScaleDisable).w               | scaling disabled?
        BEQ.B   SWAPFONT_CONT_27_CONT_10        | no -> keep computed numer
        MOVE    #0x100,0(A0,D5.W)               | yes -> force 1:1 (numer=denom)
SWAPFONT_CONT_27_CONT_10:
        RTS                                     | return after axis computed
SWAPFONT_CONT_27_CONT_11:
        NEG     D6                              | flip search direction
        BPL.W   SWAPFONT_CONT_27_CONT_4         | now positive -> give up, use ApFont
        MOVE    D4,D3                           | restore base id
        BRA.W   SWAPFONT_CONT_27_CONT_7         | retry search going downward

| ----------------------------------------------------------
| SWAPFONT_CONT_39
| SWAPFONT_CONT_39: query device driver for its DPI resolution
| D0 = device (0=screen, nonzero=printer driver refNum)
| Fills FMDotsPerInch_h/v with device resolution
SWAPFONT_CONT_39:
        TST     D0                              | device 0 (screen)?
        BEQ.B   FM_INSTALL_DEFAULTS             | yes -> reset to 80-DPI defaults
        MOVEQ.L #-0x1,D0                        | prime D0 sign-extension
        MOVE.B  6(A3),D0                        | D0 = FMInput.device byte
        MOVEQ.L #0x32,D1                        | D1 = sizeof(IOParam) = 50
        SUBA.L  D1,SP                           | SP -= D1
        LEA.L     24(SP),A0                     | A0 = csParam region of IOParam
        MOVE    D0,(A0)+                        | ioRefNum = driver id
        MOVE    #0x8,(A0)+                      | csCode 8 = GetDeviceMetrics
        LEA.L     (FMDotsPerInch_h).w,A1        | A1 = result buffer (DPI)
        MOVE.L  A1,(A0)+                        | csParam[1] = DPI buffer ptr
        MOVE    6(A3),(A0)+                     | ioVRefNum = device id
        MOVE.L  SP,A0                           | A0 = IOParam ptr
        _Status                                 | ask printer driver for DPI
        ADDA.L  D1,SP                           | SP += D1 (unwind IOParam)
        RTS                                     | return with DPI in low memory
FM_INSTALL_DEFAULTS:
        LEA.L     (FMDotsPerInch_h).w,A1        | A1 = FMOutput defaults destination
        LEA     FM_DEFAULTS_DATA(PC),A0         | A0 = ROM defaults table (28 bytes)
        MOVEQ.L #0x1C,D0                        | D0 = 28 bytes to copy
        _BlockMove                              | reset FMOutput defaults at boot
        RTS                                     | return after defaults installed

| ----------------------------------------------------------
| FM_DEFAULTS_DATA @ $B548 -- 100-byte default FMOutput + cursor table
|
| 28-byte FMOutput record copied by FM_INSTALL_DEFAULTS (via _BlockMove
| with D0=0x1C) to (FMDotsPerInch_h). Layout:
| +0 vDotsPerInch = 80 dpi
| +2 hDotsPerInch = 80 dpi
| +4 bold = extra, offset (00,01)
| +6 italic = shadow,extra (01,01)
| +8 ulOffset = 0x08 (8 pixels below baseline)
| +9 ulShadow = 0x01
| +10 ulThick = 0
| +11 shadow = 0
| +12..+27 = (0,5,1,1,5,2,2,0, 0,FF,0,0, 1,1,1,1)
| outline + condense/extend + UL stroke params
|
| Bytes 28-99 are the 72-byte default arrow-cursor bitmap + mask +
| hotspot that InitCursor installs at boot. The same layout is used
| by Plus (see src/plus/toolbox/font_mgr.s:SWAPFONT_CONT_45, which
| is the same data block under the FDisasm-generated Plus name).
|
| The FDisasm output below is byte-identical to the ROM but shows
| the region as pseudo-instructions because the bytes happen to
| decode; they are data and are never executed as code.
| ----------------------------------------------------------
FM_DEFAULTS_DATA:
  .byte 0x00, 0x50, 0x00, 0x50, 0x00, 0x01, 0x01, 0x01, 0x08, 0x01, 0x00, 0x00
  .byte 0x00, 0x05, 0x01, 0x01, 0x05, 0x02, 0x02, 0x00, 0x00, 0xFF, 0x00, 0x00
  .byte 0x01, 0x01, 0x01, 0x01                  | FMOutput defaults (28 bytes)
  .byte 0x00, 0x77, 0x7A, 0x3B, 0xC9, 0x35, 0x30, 0x19
  .byte 0x80, 0xAF, 0x30, 0x18, 0x7A, 0x60, 0x18, 0x09
  .byte 0x00, 0x60, 0x31, 0x98, 0x09, 0x72, 0x7B, 0xBA
  .byte 0x49, 0xBF, 0xE0, 0x9D, 0x01, 0x02, 0x20, 0xBF
  .byte 0x40, 0x88, 0x01, 0xF1, 0xFE, 0x02, 0x0A, 0x81
  .byte 0xBC, 0x04, 0x07, 0x03, 0x9A, 0x08, 0x04, 0x0F
FM_DEFAULTS_DATA_CONT:                          | internal data-region label
  .byte                                0x80, 0x99, 0x1F, 0xC0, 0x37, 0x60, 0xB9, 0x0F
  .byte 0x04, 0x03, 0xDF, 0x0F, 0x98, 0x08, 0x37, 0x60
  .byte 0x1F, 0xC1, 0xA8, 0x04
FM_DEFAULTS_DATA_CONT_2:                        | internal data-region label
  .byte                   0x0F, 0x80, 0x02, 0x02, 0x9A, 0x01, 0x04, 0x87
  .byte 0x08, 0x00                              | end of the default data
| ----------------------------------------------------------
|
| _GetFName ($A8FF): return the name of a font family
| Pascal: PROCEDURE GetFontName(fontNum: INTEGER; VAR theName: Str255);
| With ResLoad off, gets the FONT resource with ID fontNum*128 (the
| family's name resource; fontNum 1 = ApFontID) via SWAPFONT_CONT_27 and
| copies its resource name with _GetResInfo; theName := '' if there is
| no such resource. Saves and restores D3.
| Apple source name: GetFontName (MacSEROM.lst: GETFONTNAME)
|
GetFName:
        MOVE.L  D3,-(SP)                        | save D3
        CLR     (ResLoad).w                     | suppress resource auto-load
        MOVE    0xC(SP),D3                      | D3 = fontNum from stack
        CMPI    #0x1,D3                         | application font family?
        BNE.B   GETFNAME_CONT_2                 | no -> use caller's ID directly
        MOVE    (ApFontID).w,D3                 | yes -> substitute app font ID ($984)
GETFNAME_CONT_2:
        ASL     #0x7,D3                         | D3 = FONT resource ID (ID << 7)
        BSR.W   SWAPFONT_CONT_27                | GetResource('FONT', D3) -> A0/D0, Z if nil
        BEQ.B   GETFNAME_FOUND_2                | not found -> return empty name
        MOVE.L  A0,-(SP)                        | push FONT handle (GetResInfo param)
        PEA.L   (scratch8).w                    | push @theID (scratch8)
        MOVE.L  (SP),-(SP)                      | push @theType (same scratch8)
        MOVE.L  0x14(SP),-(SP)                  | push @theName (caller's VAR)
        _GetResInfo                             | fill name string
GETFNAME_EXIT:
        ST      (ResLoad).w                     | restore auto-load flag
        MOVE.L  (SP)+,D3                        | restore D3
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x6,SP                         | strip familyID + name ptr
        JMP     (A0)                            | return
GETFNAME_FOUND_2:
        MOVEA.L 0x8(SP),A0                      | A0 = caller's name buffer
        CLR     (A0)                            | store empty Pascal string (length=0)
        BRA.B   GETFNAME_EXIT                   | -> clean up and return

| ----------------------------------------------------------
| GetFNum -- _GetFNum ($A900).
| Pascal: procedure GetFNum(fontName: Str255; VAR theNum: INTEGER);
| Resolves a font name to a family ID. Classic 1984 looks up only
| the FONT resource (since FOND was added in Plus 1986); Plus tries
| FOND first and falls back to FONT.
GetFNum:
        LINK    A6,#-0x10E                      | set up stack frame
        CLR     (ResLoad).w                     | suppress resource auto-load
        SUBQ.W  #0x4,SP                         | space for handle result
        MOVE.L  #0x464F4E54,-(SP)               | 'FONT' resource type
        MOVE.L  12(A6),-(SP)                    | push fontName
        _GetNamedResource                       | search by name
        MOVE.L  (SP)+,D0                        | D0 = FONT handle (or NIL)
        BEQ.B   SWAPFONT_CONT_45_CONT_4         | not found ->
        MOVE.L  D0,-(SP)                        | push handle for GetResInfo
        PEA.L     -4(A6)                        | push ptr for resID result
        PEA.L     -8(A6)                        | push ptr for resType result
        PEA.L     -0x10E(A6)                    | push ptr for resName result
        _GetResInfo                             | get resource info -> locals
        MOVE.L  8(A6),A0                        | A0 = caller's VAR theNum
        MOVE    -4(A6),D0                       | D0 = resource ID
        LSR     #0x7,D0                         | extract family ID (ID >> 7)
        MOVE    D0,(A0)                         | store family in caller's VAR
SWAPFONT_CONT_45_CONT_3:
        ST      (ResLoad).w                     | (ResLoad).w := -1 (true)
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x8,SP                         | strip 8 bytes of Pascal params
        JMP     (A0)                            | RTS
SWAPFONT_CONT_45_CONT_4:
        MOVE.L  8(A6),A0                        | A0 = caller's VAR theNum
        CLR     (A0)                            | store 0 (not found)
        BRA.B   SWAPFONT_CONT_45_CONT_3         | -> common cleanup

| ----------------------------------------------------------
| SetFontLock -- _SetFontLock ($A903).
| Pascal: procedure SetFontLock(lockFlag: BOOLEAN);
| Locks/unlocks the current font in memory by toggling the
| purgeable bit on the font handle. Classic 1984 calls
| _ReleaseResource on the lock side (Plus 1986 just sets the
| bit); also no LastFOND tracking (no FOND resources in 1984).
SetFontLock:
        MOVE.L  (FOutFontHandle).w,A1           | A1 = current font handle
        MOVE.L  A1,-(SP)                        | push handle for trap
        TST.B   8(SP)                           | lockFlag from caller
        BNE.B   SWAPFONT_CONT_45_NO             | true -> unlock path
        BSET    #0x6,(A1)                       | make font purgeable (paradoxical lock)
        _ReleaseResource                        | release back to ResMgr
SWAPFONT_CONT_45_CONT_5:
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x2,SP                         | strip param
        JMP     (A0)                            | RTS
SWAPFONT_CONT_45_NO:
        _LoadResource                           | reload if purged
        BCLR    #0x6,(A1)                       | make non-purgeable
        BRA.B   SWAPFONT_CONT_45_CONT_5         | strip param + return

| ----------------------------------------------------------
| RealFont -- _RealFont ($A902).
| Pascal: function RealFont(fontNum: INTEGER; size: INTEGER): BOOLEAN;
| Tests whether a font/size combination exists without scaling.
| Classic 1984 looks up only the FONT resource directly; Plus 1986
| tries FOND first (with full association table walk) and falls
| back to FONT.
RealFont:
        CLR     8(SP)                           | result = false initially
        CLR     (ResLoad).w                     | suppress resource auto-load
        MOVE    6(SP),D0                        | D0 = font family
        ASL     #0x7,D0                         | family << 7 (build FONT res-ID base)
        MOVE    4(SP),D1                        | D1 = requested size
        ANDI    #0x7F,D1                        | mask to 7 bits
        BEQ.B   SWAPFONT_CONT_45_CONT_6         | size 0 -> not real
        OR      D1,D0                           | D0 = FONT resource ID
        SUBQ.W  #0x4,SP                         | space for handle result
        MOVE.L  #0x464F4E54,-(SP)               | 'FONT' resource type
        MOVE    D0,-(SP)                        | push res-ID
        _GetResource                            | look up FONT
        TST.L   (SP)+                           | got handle?
        BEQ.B   SWAPFONT_CONT_45_CONT_6         | no -> result stays false
        ADDQ.B  #0x1,8(SP)                      | result = true
SWAPFONT_CONT_45_CONT_6:
        ST      (ResLoad).w                     | (ResLoad).w := -1 (true)
        MOVE.L  (SP)+,(SP)                      | strip return address slot
        RTS                                     | return BOOLEAN result on stack
