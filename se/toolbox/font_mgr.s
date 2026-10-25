| Font Manager
|
| Apple source: FontMgr.a (MacSEROM.lst module FONTMANAGER): InitFonts,
| FMSwapFont (with FPOINTONE), GetFName ($A8FF), RealFont ($A902), GetFNum
| ($A900), SetFontLock ($A903), SetFScaleDisable ($A834), FontMetrics
| ($A835): finding the font strike for FMInput (family, size, style,
| FOND and FONT resources), the style adjustments and the width tables.
|
| References: Inside Macintosh Vol I, Ch 7 and Vol IV, Ch 5 (The Font
| Manager)

| ====================================================================
|
| InitFonts (FONTMANAGER) -- Font Manager initialization
|
| Called once at boot from InitToolBox. Sets up:
|   FOutError, FOutFontHandle, FONDID, LastFOND -- result slots
|   SWAPFONT_OK_16 -- prebuild width-table cache infrastructure
|   CurFMDevice, FScaleDisable, FractEnable, FontFlag -- modes
|   ApFontID = SPFont + 1 (Geneva 12 by default)
|   FMDefaultSize = 12 -- default size when caller passes 0
|   WidthTabHandle -- 1070-byte (= 0x42E) sysHeap handle
|   WidthListHand  -- 12 widthTab handles (48 = 0x30 bytes)
|   JSwapFont -- jump-vector to FMSwapFont
| Then calls _FMSwapFont (1,1)/(0,0)(0) to install the System
| (Chicago 12) font as ROMFont0 for cold boot use.
|
| Apple source module: FONTMANAGER
INITFONTS:
    CLR.W       (FOutError).W                   | clear out error
    CLR.L       (FOutFontHandle).W              | clear out font handle
    MOVEQ.L     #-0x1,D2                        | D2 = -1 (sentinel)
    MOVE.W      D2,(FONDID).W                   | mark FONDID invalid
    CLR.L       (LastFOND).W                    | clear last FOND cache
    BSR.W       SWAPFONT_OK_16                  | rebuild width-table cache
    CLR.W       (CurFMDevice).W                 | no current font device
    CLR.B       (FScaleDisable).W               | enable font scaling
    CLR.B       (FractEnable).W                 | disable fract widths
    ST.B        (FontFlag).W                    | bypass fond cache (FontFlag := true)
    MOVE.W      (SPFont).W,(ApFontID).W         | start ApFontID at SPFont
    ADDQ.W      #0x1,(ApFontID).W               | (off-by-one fixup)
    MOVE.B      #0xC,(FMDefaultSize).W          | default size = 12
    MOVE.L      (WidthTabHandle).W,D0           | already allocated ?
    BNE.B       INITFONTS_INSTALL_VECTOR        | yes, skip alloc
    MOVE.L      #0x42E,D0                       | size = 1070 bytes
    _NewHandleSys                               | alloc in sysHeap
    BNE.B       INITFONTS_ERR_2                 | error -> SysError 25
    MOVE.L      A0,(WidthTabHandle).W           | install width table
    CLR.L       (WidthListHand).W               | clear width list
    CMPI.W      #0x2,(MemTop).W                 | mini-Mac (< 128K) ?
    BLS.B       INITFONTS_INSTALL_VECTOR        | yes, skip width list
    MOVEQ.L     #0x30,D0                        | size = 48 bytes (12 handles)
    _NewHandleSysClear                          | alloc + zero in sysHeap
    BNE.B       INITFONTS_INSTALL_VECTOR        | error, skip
    MOVE.L      A0,(WidthListHand).W            | install width list
INITFONTS_INSTALL_VECTOR:
    MOVE.L      (0x1204).W,(JSwapFont).W        | install JSwapFont vector
    BSR.B       INITFONTS_CONT_2                | invalidate width-table caches
    MOVE.L      (OneOne).W,-(A7)                | numer = (1,1)
    MOVE.L      (OneOne).W,-(A7)                | denom = (1,1)
    CLR.L       -(A7)                           | family = 0 (system)
    CLR.L       -(A7)                           | face = 0 (plain)
    SUBQ.W      #0x4,A7                         | result slot
    PEA.L       0x4(A7)                         | addr of result slot
    _FMSwapFont                                 | get system font (Chicago 12)
    ADDA.W      #0x14,A7                        | strip 20 bytes of params
    MOVE.L      (FOutFontHandle).W,(ROMFont0).W | save as ROMFont0
    RTS                                         | return from InitFonts
| ----------------------------------------------------------
|
| INITFONTS_ERR_2 -- WidthTabHandle alloc failed: bail with SysError 25
|
INITFONTS_ERR_2:
    MOVEQ.L     #0x19,D0                        | error code 25
    _SysError                                   | trigger Sad Mac
| ----------------------------------------------------------
|
| INITFONTS_CONT_2 -- invalidate every cached width-table
|
| Walks the 12-entry WidthListHand array of widthTab handles and
| stamps -1 into each cached widthTab's LastSPExtra and font-id
| slots (offsets +0x400 and +0x40C in widthTab). Then falls into
| WidthTab_InvalidateAll to also invalidate the primary widthTab.
|
INITFONTS_CONT_2:
    MOVEQ.L     #-0x1,D2                        | D2 = -1 sentinel
    MOVE.L      D2,(LastSPExtra).W              | invalidate primary cache
    MOVE.L      (WidthListHand).W,D0            | got the 12-entry list ?
    BEQ.B       WidthTab_InvalidateAll          | no, just invalidate primary
    MOVEA.L     D0,A1                           | A1 -> WidthListHand
    MOVEA.L     (A1),A1                         | dereference
    MOVEQ.L     #0xB,D1                         | D1 = 11 (DBF for 12 entries)
INITFONTS_LIST_LOOP:
    MOVE.L      (A1)+,D0                        | get next widthTab handle
    BEQ.B       WidthTab_InvalidateAll          | nil entry, stop
    MOVEA.L     D0,A0                           | A0 -> handle
    MOVE.L      (A0),D0                         | dereference
    BEQ.B       INITFONTS_SKIP                  | purged, skip
    MOVEA.L     (A0),A0                         | A0 -> widthTab
    MOVE.L      D2,0x400(A0)                    | mark LastSPExtra invalid
    MOVE.W      D2,0x40C(A0)                    | mark font-id invalid
INITFONTS_SKIP:
    DBF.W       D1,INITFONTS_LIST_LOOP          | loop 12 entries
| ----------------------------------------------------------
|
| WidthTab_InvalidateAll -- invalidate the primary cached widthTab
|
| Stamps -1 into LastSPExtra and font-id slots of the WidthTabHandle
| widthTab (the one returned by WidthTab_DerefPrimary), and clears CurFMFamily.
|
| Called by: INITFONTS_CONT_2, INITFONTS_LIST_LOOP, FMSWAPFONT, FMSWAPFONT_RETRY_OK, FMSWAPFONT_REFRESH_PRIMARY (and 1 more)
WidthTab_InvalidateAll:
    MOVEQ.L     #-0x1,D2                        | D2 = -1 sentinel
    BSR.B       WidthTab_DerefPrimary           | A0 -> primary widthTab
    MOVE.L      D2,0x400(A0)                    | mark LastSPExtra invalid
    MOVE.W      D2,0x40C(A0)                    | mark font-id invalid
    MOVE.W      D2,(CurFMFamily).W              | mark CurFMFamily invalid
    RTS                                         | return from WidthTab_InvalidateAll
| ----------------------------------------------------------
|
| WidthTab_DerefPrimary -- A0 := *(WidthTabHandle)
|
| Returns the dereferenced WidthTabHandle (the primary widthTab
| pointer) in A0. Used by all routines that need to read or
| modify the primary cached widthTab.
|
| Called by: FMSWAPFONT_BUILD_WIDTH, WidthTab_InvalidateAll, FMSWAPFONT_EXTRA_INIT, SWAPFONT_SKIP_4, SWAPFONT_CONT_3 (and 4 more)
WidthTab_DerefPrimary:
    MOVEA.L     (WidthTabHandle).W,A0           | A0 = WidthTabHandle
    MOVEA.L     (A0),A0                         | A0 = *(WidthTabHandle)
    RTS                                         | return from WidthTab_DerefPrimary
| ----------------------------------------------------------
|
| ResolveFontFamSize -- resolve (family, size) defaults from a font input
|
| A3 -> font input record (CurFMFamily / FOutFamily layout):
|   +0 W familyID (0 -> system font)
|   +2 W size     (0 -> default size)
|
| Returns D0 = packed (family<<16 | size) with system / default
| substitutions applied:
|   family 0 -> SysFontFam, default size = SysFontSize
|   family 1 (ApplFont) -> ApFontID
|   default size -> FMDefaultSize, else 12
|
ResolveFontFamSize:
    MOVEQ.L     #0x0,D1                         | D1 = 0 (default size sentinel)
    MOVE.W      (A3),D0                         | D0 = familyID
    BNE.B       ResolveFontFamSize_DefSize      | non-zero, skip system substitution
    MOVE.W      (SysFontFam).W,D0               | family 0 -> SysFontFam
    MOVE.W      (SysFontSize).W,D1              | use SysFontSize as default
    BNE.B       ResolveFontFamSize_Pack         | got valid size, done with size
ResolveFontFamSize_DefSize:
    MOVE.B      (FMDefaultSize).W,D1            | use FMDefaultSize
    BNE.B       ResolveFontFamSize_GotSize      | non-zero, ok
    MOVEQ.L     #0xC,D1                         | else default to 12
ResolveFontFamSize_GotSize:
    CMPI.W      #0x1,D0                         | family 1 (ApplFont) ?
    BNE.B       ResolveFontFamSize_Pack         | no, skip
    MOVE.W      (ApFontID).W,D0                 | yes, substitute ApFontID
ResolveFontFamSize_Pack:
    SWAP.W      D0                              | family in hi word
    MOVE.W      0x2(A3),D0                      | get caller's size
    BNE.B       ResolveFontFamSize_Done         | non-zero, use it
    MOVE.W      D1,D0                           | else use computed default
ResolveFontFamSize_Done:
    RTS                                         | return D0 = packed (family,size)
| ====================================================================
|
| _FMSwapFont (FMSWAPFONT) -- swap to a different font
|
| The Font Manager's main entry point. Called from QuickDraw
| StdText / TextWidth, the Toolbox SetFont, and from InitFonts
| at boot. Stack on entry:
|   +4  L  inputAddr  -> FOutFamily / FOutSize / FOutFace ...
|   +8  L  outputAddr -> FOutError / FOutFontHandle / numer / etc.
|
| The routine:
|   1. Compares input (CurFMInput) against last call (CurFMFamily)
|      to short-circuit if identical (ignoring scale numer/denom).
|   2. If changed, dispatches to FMSWAPFONT_BODY / FMSWAPFONT_PUBLISH_EXTRA to actually
|      load + scale + cache the new font.
|   3. Updates WidthPtr to point at the active widthTab.
|
| Returns via the address now at 0(A7) (the original 0x8(A7) was
| replaced with FOutError pointer at entry).
|
FMSWAPFONT:
    LEA.L       (FOutError).W,A0                | A0 -> FOutError block
    MOVE.L      A0,0x8(A7)                      | overwrite outputAddr param with FOutError
    MOVEQ.L     #-0x1,D2                        | D2 = -1 sentinel
    CMP.L       (LastSPExtra).W,D2              | width-table cache invalid ?
    BEQ.W       FMSWAPFONT_FALLBACK             | yes, force full reload
    ADDQ.B      #0x1,(FontFlag).W               | bump FontFlag (sticky)
    BEQ.B       FMSWAPFONT_TRY_FAST             | wrap to 0 (was 0xFF), fast path
    BSR.B       WidthTab_InvalidateAll          | else invalidate cache
    CMPI.B      #0x9,(FontFlag).W               | reached saturation (9) ?
    BEQ.W       FMSWAPFONT_SYSMAP_ENTRY         | yes, special case
    BGT.W       SWAPFONT_CONT                   | past saturation, just publish
    MOVE.B      #0x8,(FontFlag).W               | clamp to 8
FMSWAPFONT_TRY_FAST:
    MOVEA.L     0x4(A7),A0                      | A0 -> input record (CurFMInput)
    LEA.L       (CurFMFamily).W,A1              | A1 -> last-call cache
    CMPM.L      (A0)+,(A1)+                     | family/size match ?
    BEQ.B       FMSWAPFONT_FAST_CMP1            | yes, check face/style next
    MOVE.L      A3,-(A7)                        | save A3
    MOVEA.L     0x8(A7),A3                      | A3 -> input record (defaults)
    BSR.B       ResolveFontFamSize              | resolve input defaults -> D0
    MOVE.L      D0,D2                           | D2 = resolved (family,size)
    LEA.L       (CurFMFamily).W,A3              | A3 -> last-call cache
    BSR.B       ResolveFontFamSize              | resolve cache defaults -> D0
    MOVEA.L     (A7)+,A3                        | restore A3
    CMP.L       D2,D0                           | match after defaults ?
    BNE.B       FMSWAPFONT_FALLBACK             | no, full reload
    MOVE.L      -0x4(A0),-0x4(A1)               | propagate input family/size
FMSWAPFONT_FAST_CMP1:
    CMPM.L      (A0)+,(A1)+                     | face/style match ?
    BEQ.B       FMSWAPFONT_FAST_CMP2            | yes
    MOVE.L      -(A0),D0                        | back up to face long
    MOVE.L      -(A1),D1                        | (cache copy)
    EOR.L       D0,D1                           | bits that differ
    ANDI.L      #0xFF00FFFF,D1                  | mask out only the face byte
    BNE.B       FMSWAPFONT_FALLBACK             | other bits differ -> reload
    MOVE.L      (A0)+,(A1)+                     | propagate face change
FMSWAPFONT_FAST_CMP2:
    CMPM.L      (A0)+,(A1)+                     | numer match ?
    BNE.B       FMSWAPFONT_FALLBACK             | no, reload
    CMPM.L      (A0)+,(A1)+                     | denom match ?
    BNE.B       FMSWAPFONT_FALLBACK             | no, reload
    TST.B       (QDExist).W                     | QuickDraw initialized ?
    BMI.B       FMSWAPFONT_RETRY_DEC            | no, skip QD-specific check
    MOVEA.L     (A5),A0                         | A0 -> QD globals
    MOVE.L      (A0),D0                         | thePort = ?
    BEQ.B       FMSWAPFONT_RETRY_DEC            | no port, skip
    MOVEA.L     D0,A0                           | A0 -> thePort
    MOVE.L      (LastSPExtra).W,D0              | D0 = cached SpExtra
    CMP.L       0x4C(A0),D0                     | match thePort.spExtra ?
    BEQ.B       FMSWAPFONT_RETRY_DEC            | yes, fast path
    LINK        A6,#-0x4A                       | else allocate frame for slow path
    CLR.W       -0x48(A6)                       | clear scratch slot
    MOVEM.L     D3-D7/A2-A4,-(A7)               | save regs
    MOVEA.L     0x8(A6),A3                      | A3 -> FOutError block
    SUBQ.B      #0x2,(FontFlag).W               | dec FontFlag for retry
    BRA.W       FMSWAPFONT_PUBLISH_EXTRA        | jump to slow rebuild path
| Common reload path: jump to full FMSwapFont implementation.
| Called by: FMSWAPFONT_FAST_CMP2, FMSWAPFONT, FMSWAPFONT_TRY_FAST, FMSWAPFONT_FAST_CMP1, SWAPFONT_EXIT
FMSWAPFONT_FALLBACK:
    BRA.B       FMSWAPFONT_BODY                 | full font load + cache rebuild
FMSWAPFONT_RETRY_DEC:
    SUBQ.B      #0x2,(FontFlag).W               | dec FontFlag for retry
SWAPFONT_EXIT:
    MOVEA.L     (FOutFontHandle).W,A0           | A0 -> cached font handle
    TST.L       (A0)                            | already loaded ?
    BNE.B       SWAPFONT_CONT                   | yes, just publish width ptr
    BSR.B       FMLoadFont_Force                | else _LoadResource it
    BEQ.B       FMSWAPFONT_FALLBACK             | failed -> reload
    MOVEA.L     (FOutFontHandle).W,A0           | re-fetch handle
    BSR.W       BUILDBBOX_BODY                  | post-load fixup
SWAPFONT_CONT:
    MOVEA.L     (WidthTabHandle).W,A0           | A0 -> WidthTab handle
    MOVE.L      (A0),(WidthPtr).W               | publish dereferenced ptr
    ST.B        (FontFlag).W                    | FontFlag := true (in cache)
    MOVEA.L     (A7)+,A0                        | pop return addr
    ADDQ.W      #0x4,A7                         | strip 1 param
    JMP         (A0)                            | tail-call back
| ----------------------------------------------------------
|
| SWAPFONT_CONT_13 -- store one numerator coord and packed denom-fract
|
| D1 = byte offset (0=v, 2=h) within FOutNumer / FScaleVFact slots.
| A1 -> source: [numer_word, denom_word] for one axis
| Side effect: A1 advances past the numer word.
|
| Writes:
|   FOutNumer_h[D1]  := A1[0] (numer)
|   FScaleVFact[-D1*2] := A1[2] << 8 (denom * 256, fixed-point)
|
SWAPFONT_CONT_13:
    LEA.L       (FOutNumer_h).W,A0              | A0 -> FOutNumer base
    MOVE.W      (A1)+,0x0(A0,D1.W)              | numer -> FOutNumer[D1]
    LEA.L       (FScaleVFact).W,A0              | A0 -> FScaleVFact base
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.W      0x2(A1),D0                      | D0 = denom word (after numer)
    ASL.L       #0x8,D0                         | scale to fixed-point (* 256)
    ADD.W       D1,D1                           | D1 *= 2 (long-word stride)
    NEG.W       D1                              | negate (downward)
    MOVE.L      D0,0x0(A0,D1.W)                 | scaled denom -> FScaleVFact[-2*D1]
    RTS                                         | return from SWAPFONT_CONT_13
| ----------------------------------------------------------
|
| FMLoadFont_Maybe / FMLoadFont_Force -- de-reference a font resource handle,
| loading it from disk if purged.
|
| A0 -> handle. Returns A0 = master pointer (handle dereferenced).
|
| FMLoadFont_Maybe: short-circuit if handle is already loaded.
| FMLoadFont_Force: force a _LoadResource and abort (FMSWAPFONT_RETRY_TAIL) on
|   failure -- typically used when the caller has already
|   determined the handle was purged.
|
FMLoadFont_Maybe:
    TST.L       (A0)                            | already loaded ?
    BNE.B       SWAPFONT_NO_16                  | yes, just dereference
FMLoadFont_Force:
    MOVE.L      A0,-(A7)                        | save handle
    MOVE.W      #0xFFFF,(ROMMapInsert).W        | enable ROM-map override
    _LoadResource                               | load from disk
    CMPI.B      #0xFF,(FontFlag).W              | font swap aborted ?
    BEQ.B       FMSWAPFONT_ABORT                | yes, jump to FMSWAPFONT_RETRY_TAIL
    TST.L       (A0)                            | load succeeded ?
    BEQ.B       FMSWAPFONT_ABORT                | no, jump to FMSWAPFONT_RETRY_TAIL
SWAPFONT_NO_16:
    MOVEA.L     (A0),A0                         | dereference handle
    RTS                                         | return from SWAPFONT_NO_16
FMSWAPFONT_ABORT:
    BRA.W       FMSWAPFONT_RETRY_TAIL           | abort font swap
| ====================================================================
|
| FMSWAPFONT_BODY -- FMSwapFont slow path: full rebuild
|
| Reached when FMSwapFont's quick check decided the cached state
| doesn't match. Allocates 74 bytes of locals, copies caller's
| input record (16 bytes) to -0x10(A6), normalizes (family,size)
| via ResolveFontFamSize, then walks the WidthListHand cache for a hit.
| On a hit the cached widthTab + FOND + per-font state is published
| to FOutFontHandle and friends. On a miss, drops through to the
| build-from-scratch path at FMSWAPFONT_CACHE_MISS (font + widthTab assembly).
|
FMSWAPFONT_BODY:
    LINK        A6,#-0x4A                       | reserve 74 bytes locals
    CLR.W       -0x48(A6)                       | clear age slot
    MOVEM.L     D3-D7/A2-A4,-(A7)               | save scratch regs
FMSWAPFONT_NORMALIZE:
    MOVEA.L     0x8(A6),A0                      | A0 -> caller's FOutFamily input rec
    LEA.L       -0x10(A6),A1                    | A1 -> local copy slot
    MOVEQ.L     #0x10,D0                        | 16 bytes (full input record)
    _BlockMove                                  | copy input -> local
    MOVEA.L     A1,A3                           | A3 -> normalized input rec
    MOVE.B      0x4(A3),(FOutUnused).W          | save face byte
    MOVE.W      0x6(A3),D0                      | D0 = caller's device
    CMP.W       (CurFMDevice).W,D0              | matches current ?
    BEQ.B       FMSWAPFONT_DEVICE_OK            | yes, skip device-change reset
    BSR.W       SWAPFONT_CONT_39                | else reset CurFMDevice cache
FMSWAPFONT_DEVICE_OK:
    BSR.W       ResolveFontFamSize              | normalize (family,size) defaults
    MOVE.L      D0,(A3)                         | install resolved family,size
    CLR.B       0x5(A3)                         | clear unused byte
    LEA.L       (FontFlag).W,A4                 | A4 -> FontFlag
    CMPI.B      #0x6,(A4)                       | retry counter >= 6 ?
    BLT.B       FMSWAPFONT_RETRY_OK             | no, normal flow
    CLR.W       (A3)                            | yes, force family = 0 (system)
FMSWAPFONT_RETRY_OK:
    TST.B       (A4)                            | FontFlag negative ?
    BPL.B       SWAPFONT_NO_12                  | no, ok
    BSR.W       WidthTab_InvalidateAll          | yes, invalidate caches
    CLR.B       (A4)                            | clear FontFlag
SWAPFONT_NO_12:
    MOVE.L      (WidthListHand).W,D0            | got 12-entry width-list ?
    BEQ.B       FMSWAPFONT_BUILD_FROM_SCRATCH   | no, build from scratch
    MOVEQ.L     #-0x1,D2                        | sentinel
    CMP.L       (LastSPExtra).W,D2              | LastSPExtra still invalid ?
    BEQ.B       FMSWAPFONT_INVALIDATE_ALL       | yes, force re-init
    CMP.W       (CurFMFamily).W,D2              | CurFMFamily invalid ?
    BNE.B       SWAPFONT_NO_14                  | no, scan width-list cache
    BRA.B       FMSWAPFONT_BUILD_FROM_SCRATCH   | yes, build from scratch
FMSWAPFONT_INVALIDATE_ALL:
    BSR.W       INITFONTS_CONT_2                | invalidate every cached widthTab
FMSWAPFONT_BUILD_FROM_SCRATCH:
    BRA.W       FMSWAPFONT_REFRESH_PRIMARY      | jump to build-from-scratch path
| SWAPFONT_NO_14 -- walk WidthListHand looking for matching cached entry
SWAPFONT_NO_14:
    MOVEA.L     D0,A4                           | A4 -> WidthListHand
    MOVEA.L     (A4),A4                         | deref to handle array
    MOVEQ.L     #-0x1,D2                        | D2 = -1 (best-LRU sentinel)
    MOVEQ.L     #-0x1,D3                        | D3 = -1 (FOND-match slot index)
    SF.B        D4                              | D4 = false (size-match flag)
    MOVEQ.L     #-0x4,D5                        | D5 = -4 (slot index counter)
    SF.B        D6                              | D6 = false (full-hit flag)
    MOVEQ.L     #-0x1,D7                        | D7 = -1 (best-LRU index)
FMSWAPFONT_CACHE_LOOP:
    ADDQ.W      #0x4,D5                         | next slot index
    MOVE.L      (A4),D1                         | D1 = handle at this slot
    BEQ.B       FMSWAPFONT_CACHE_MISS           | nil entry, end-of-cache marker
    MOVEA.L     D1,A0                           | A0 -> handle
    MOVE.L      (A0),D0                         | D0 = master ptr (purged ?)
    BEQ.B       FMSWAPFONT_CACHE_PURGED         | yes, purged, skip
    MOVE.W      D5,D7                           | D7 = LRU index of last live entry
    MOVEA.L     D0,A1                           | A1 -> widthTab
    MOVEQ.L     #0x3,D1                         | D1 = 3 (4 longs to compare)
    MOVEA.L     A3,A0                           | A0 -> input rec
    LEA.L       0x40C(A1),A1                    | A1 -> widthTab font-id slot
    CMPI.W      #0xFFFF,(A1)                    | invalid (-1) ?
    BNE.B       FMSWAPFONT_CACHE_CMP            | no, check it
    MOVE.W      D5,D3                           | yes, remember as recyclable
FMSWAPFONT_CACHE_CMP:
    CMPM.L      (A0)+,(A1)+                     | input matches widthTab key ?
    DBNE.W      D1,FMSWAPFONT_CACHE_CMP         | loop 4 longs, stop on mismatch
    BNE.B       SWAPFONT_NEXT_2                 | mismatch, try next entry
| Cache hit: publish cached state.
    ST.B        D6                              | mark full-hit
    MOVE.W      (A1)+,(FONDID).W                | FONDID := cached
    MOVEA.L     (A1)+,A0                        | A0 = cached FOND handle
    MOVE.L      A0,(LastFOND).W                 | publish LastFOND
    BEQ.B       SWAPFONT_SKIP_5                 | nil FOND, skip strike-load
    BSR.W       FMLoadFont_Maybe                | load FOND if purged
    MOVE.B      (A0),(GotStrike).W              | GotStrike := first byte of FOND
SWAPFONT_SKIP_5:
    MOVE.B      (A1)+,(UsedFWidth).W            | UsedFWidth from cache
    MOVE.B      (A1)+,(FOutUnused).W            | FOutUnused from cache
    MOVEQ.L     #0x0,D1                         | D1 = 0 (v offset)
    BSR.W       SWAPFONT_CONT_13                | install scale numer/denom (v)
    MOVEQ.L     #0x2,D1                         | D1 = 2 (h offset)
    BSR.W       SWAPFONT_CONT_13                | install scale numer/denom (h)
    MOVEA.L     (A4),A0                         | A0 -> cache slot handle
    MOVEA.L     (A0),A1                         | A1 -> widthTab
    MOVEA.L     0x400(A1),A1                    | A1 = widthTab.fontHandle
    MOVE.L      A1,(FOutFontHandle).W           | publish to FOutFontHandle
    BRA.B       FMSWAPFONT_LRU_ENTER            | -> common cache-hit tail
FMSWAPFONT_CACHE_PURGED:
    MOVE.W      D5,D2                           | D2 = remember purged-cache slot index
SWAPFONT_NEXT_2:
    ADDQ.W      #0x4,A4                         | next 4-byte cache slot
    CMPI.W      #0x2C,D5                        | walked all 12 entries (44 bytes) ?
    BCS.B       FMSWAPFONT_CACHE_LOOP           | no, keep scanning
    ST.B        D4                              | yes, mark "all entries scanned"
    SUBQ.W      #0x4,A4                         | back up to last valid slot
| FMSWAPFONT_CACHE_MISS -- cache miss: try to allocate or recycle a slot.
FMSWAPFONT_CACHE_MISS:
    MOVEA.L     (WidthTabHandle).W,A1           | A1 -> primary widthTab
    MOVEA.L     (A1),A1                         | deref handle
    CMPI.W      #0xFFFF,0x40C(A1)               | primary widthTab font-id invalid ?
    BEQ.B       FMSWAPFONT_REFRESH_PRIMARY      | yes, just refresh primary
    EXG         D3,D5                           | swap: D5 = recyclable-slot, D3 = LRU
    TST.W       D5                              | got a recyclable (FFFF) slot ?
    BPL.B       SWAPFONT_CONT_16                | yes, reuse it
    MOVE.L      #0x42E,D1                       | D1 = 1070 bytes (widthTab size)
    MOVEA.L     (TheZone).W,A1                  | save current zone
    MOVE.L      (SysZone).W,(TheZone).W         | switch to sysHeap for alloc
    _FreeMem                                    | D0 = max free bytes available
    MOVE.L      A1,(TheZone).W                  | restore current zone
    CMP.L       D1,D0                           | enough free for new widthTab ?
    BLE.B       FMSWAPFONT_CACHE_LRU            | no, evict LRU
    MOVE.L      D1,D0                           | yes, alloc 1070 bytes
    MOVE.W      D2,D5                           | try purged-cache slot first
    BPL.B       SWAPFONT_CONT_16                | got one, install
    TST.B       D4                              | scanned all entries ?
    BNE.B       FMSWAPFONT_CACHE_LRU            | yes, evict LRU
    MOVE.W      D3,D5                           | else use FFFF slot
    _NewHandleSys                               | allocate new widthTab in sysHeap
    BNE.B       FMSWAPFONT_REFRESH_PRIMARY      | failed, just refresh primary
    BRA.B       SWAPFONT_CONT_16                | success, install
FMSWAPFONT_CACHE_LRU:
    MOVE.W      D7,D5                           | D5 = LRU slot index (last live)
    BMI.B       FMSWAPFONT_REFRESH_PRIMARY      | nothing to evict, refresh primary
| SWAPFONT_CONT_16 -- install new widthTab handle into cache slot D5.
SWAPFONT_CONT_16:
    MOVEA.L     (WidthListHand).W,A4            | A4 -> WidthListHand handle
    MOVEA.L     (A4),A4                         | deref to slot array
    LEA.L       0x0(A4,D5.W),A4                 | A4 -> chosen slot
    MOVE.L      (A4),D1                         | D1 = existing slot handle (if any)
    BEQ.B       FMSWAPFONT_LRU_ENTER            | empty slot, skip realloc
    MOVEA.L     D1,A0                           | A0 -> existing handle
    TST.L       (A0)                            | already loaded ?
    BNE.B       FMSWAPFONT_LRU_ENTER            | yes, no need to realloc
    _ReallocHandle                              | reattach purged storage
    BNE.B       FMSWAPFONT_REFRESH_PRIMARY      | failed, refresh primary
    BRA.B       SWAPFONT_CONT_16                | retry slot
FMSWAPFONT_LRU_ENTER:
    BRA.B       FMSWAPFONT_LRU_DEC              | enter compact loop
| LRU shuffle: move slot[i] -> slot[i+1] from D5 down to slot 0.
FMSWAPFONT_LRU_SHIFT:
    MOVE.L      -(A4),0x4(A4)                   | shift slot down
FMSWAPFONT_LRU_DEC:
    SUBQ.W      #0x4,D5                         | dec slot index
    BPL.B       FMSWAPFONT_LRU_SHIFT            | loop while >= 0
    MOVE.L      (WidthTabHandle).W,D1           | D1 = old primary widthTab
    MOVE.L      A0,(WidthTabHandle).W           | install new widthTab as primary
    _HNoPurge                                   | mark new widthTab non-purgeable
    MOVE.L      D1,(A4)                         | demote old primary into slot 0
    MOVEA.L     D1,A0                           | A0 = old primary handle
    _HPurge                                     | mark it purgeable
    TST.B       D6                              | full-hit flag set ?
    BNE.B       SWAPFONT_CONT_18                | yes, skip rebuild header
| FMSWAPFONT_REFRESH_PRIMARY -- refresh primary widthTab from FOutFontHandle.
| Called by: FMSWAPFONT_CACHE_MISS, FMSWAPFONT_BUILD_FROM_SCRATCH, FMSWAPFONT_CACHE_LRU, SWAPFONT_CONT_16
FMSWAPFONT_REFRESH_PRIMARY:
    BSR.W       WidthTab_InvalidateAll          | invalidate primary widthTab
    BSR.W       FMBuildFont                     | rebuild widthTab + FOND linkage
SWAPFONT_CONT_18:
    MOVEA.L     (FOutFontHandle).W,A0           | A0 -> selected font handle
    BSR.W       FMLoadFont_Maybe                | load if purged, deref to A0
    TST.B       (FScaleDisable).W               | scaling disabled ?
    BNE.B       SWAPFONT_OK_9                   | yes, scale via SWAPFONT_CONT_21/194F2
    LEA.L       (FOutAscent).W,A1               | A1 -> FOutAscent slot
    MOVE.B      0x13(A0),(A1)+                  | FOutAscent  := font.fontAscent
    MOVE.B      0x15(A0),(A1)+                  | FOutDescent := font.fontDescent
    MOVE.B      0x7(A0),(A1)+                   | FOutWidMax  := font.widMax
    MOVE.B      0x17(A0),(A1)                   | FOutLeading := font.leading
    BRA.B       SWAPFONT_CONT_2                 | go to style-table application
| ----------------------------------------------------------
|
| SWAPFONT_CONT_21 / SWAPFONT_CONT_22 -- scale and store one font metric
|
| Scales D0 (a font metric byte) by either FScaleVFact (vertical)
| or a caller-provided D1 (horizontal), then rounds and stores
| the result byte at *(A1)+.
|
| SWAPFONT_CONT_21: vertical -- D1 := FScaleVFact, fall through.
| SWAPFONT_CONT_22: D0 *= D1 (Fixed mul), round, store.
|
SWAPFONT_CONT_21:
    MOVE.L      (FScaleVFact).W,D1              | D1 = vertical scale factor
SWAPFONT_CONT_22:
    EXT.W       D0                              | sign-extend byte to word
    SWAP.W      D0                              | move to high half (Fixed format)
    CLR.W       D0                              | clear low half
    MOVEM.L     D0-D3/A0-A1,-(A7)               | save (D0-D3 for FixMul, A0-A1 ptrs)
    _FixMul                                     | D0 := D0 * D1 (32.0 * 16.16 = 16.16)
    _FixRound                                   | D0.W := round(D0)
    MOVE.W      (A7)+,D0                        | pop result word (others stay)
    ADDQ.W      #0x2,A7                         | strip remaining D0 high half
    MOVEM.L     (A7)+,A0-A1                     | restore A0-A1
    MOVE.B      D0,(A1)+                        | store rounded byte at *A1++
    RTS                                         | return from SWAPFONT_CONT_22
| SWAPFONT_OK_9 -- scaled metric copy: scale ascent/descent vertically,
| widMax horizontally, leading vertically.
SWAPFONT_OK_9:
    LEA.L       (FOutAscent).W,A1               | A1 -> FOutAscent slot
    MOVE.B      0x13(A0),D0                     | D0 = font.fontAscent
    BSR.B       SWAPFONT_CONT_21                | scale & store -> FOutAscent
    MOVE.B      0x15(A0),D0                     | D0 = font.fontDescent
    BSR.B       SWAPFONT_CONT_21                | scale & store -> FOutDescent
    MOVE.B      0x7(A0),D0                      | D0 = font.widMax
    MOVE.L      (FScaleHFact).W,D1              | D1 = horizontal scale
    BSR.B       SWAPFONT_CONT_22                | scale (H) & store -> FOutWidMax
    MOVE.B      0x17(A0),D0                     | D0 = font.leading
    BSR.B       SWAPFONT_CONT_21                | scale & store -> FOutLeading
| ----------------------------------------------------------
|
| SWAPFONT_CONT_2: apply font style modifications from FMStyleTab
|
| FMStyleTab is a 7-entry array of 3-byte records:
|   +0  byte offset within FOut block
|   +1  ascent/descent/extra delta (D3)
|   +2  FOutExtra delta (D4)
| Each style bit in FOutUnused selects one entry. The 8th entry
| (only read if style bit 2 = underline is set) is a 3-byte record
| of (ulOffset, ulShadow, ulThick) installed at FOutULOffset.
|
| Called during boot (1,663 times in 30s trace).
SWAPFONT_CONT_2:
    MOVE.B      (FOutUnused).W,D1               | D1 = style bits
    LEA.L       (FOutBold).W,A0                 | A0 -> FOutBold area
    CLR.L       (A0)+                           | clear bold,italic,ulOffset,ulShadow
    CLR.W       (A0)+                           | clear ulThick,extra
    CLR.B       (A0)+                           | clear pad byte
    TST.B       D1                              | any style bits set ?
    BEQ.B       FMSWAPFONT_EXTRA_INIT           | no, plain font, skip
    MOVEQ.L     #0x0,D2                         | clear D2 high
    LEA.L       (FMStyleTab).W,A1               | A1 -> FMStyleTab base
    MOVEQ.L     #0x6,D0                         | D0 = 6 (DBF for 7 styles)
    LEA.L       (FOutBold).W,A0                 | A0 -> FOutBold area
SWAPFONT_LOOP:
    MOVE.B      (A1)+,D2                        | D2 = field offset within FOut block
    MOVE.B      (A1)+,D3                        | D3 = field delta
    MOVE.B      (A1)+,D4                        | D4 = FOutExtra delta
    LSR.W       #0x1,D1                         | extract next style bit (LSB)
    BCC.B       SWAPFONT_SKIP                   | bit clear, skip this style
    ADD.B       D3,0x0(A0,D2.W)                 | apply field delta
    ADD.B       D4,(FOutExtra).W                | apply extra delta
SWAPFONT_SKIP:
    DBF.W       D0,SWAPFONT_LOOP                | loop 7 styles
    BTST        #0x2,(FOutUnused)               | underline bit set ?
    BEQ.B       FMSWAPFONT_EXTRA_INIT           | no, done
    LEA.L       (FOutULOffset).W,A0             | A0 -> FOutULOffset
    MOVE.B      (A1)+,(A0)+                     | install ulOffset
    MOVE.B      (A1)+,(A0)+                     | install ulShadow
    MOVE.B      (A1)+,(A0)+                     | install ulThick
FMSWAPFONT_EXTRA_INIT:
    BSR.W       WidthTab_DerefPrimary           | A0 = *(WidthTabHandle)
    CMPI.W      #0xFFFF,0x40C(A0)               | widthTab tagged invalid?
    BNE.W       FMSWAPFONT_PUBLISH_EXTRA        | already valid, skip rebuild
    MOVE.L      (LastFOND).W,D0                 | FOND resource loaded?
    BEQ.W       SWAPFONT_NO                     | no FOND -> use integer widths
    TST.B       (FDevDisable).W                 | device widths disabled?
    BNE.B       SWAPFONT_OK_3                   | yes, force FOND path
    TST.B       0x6(A3)                         | FMInput.device nonzero (printer)?
    BNE.W       SWAPFONT_NO                     | printer device -> integer widths
SWAPFONT_OK_3:
    BTST        #0x5,(GotStrike)                | FOND has style width table?
    BNE.B       SWAPFONT_NO                     | yes -> compute from FOND widths later
    BTST        #0x4,(GotStrike)                | FOND has width table offset?
    BNE.B       FMSWAPFONT_USE_FOND_WIDTHS      | yes -> use FOND widths
    TST.B       (FractEnable).W                 | fractional widths enabled?
    BEQ.B       SWAPFONT_NO                     | no -> use integer widths
FMSWAPFONT_USE_FOND_WIDTHS:
    MOVEA.L     D0,A0                           | A0 = LastFOND handle
    BSR.W       FMLoadFont_Maybe                | dereference + ensure loaded -> A0=ptr
    TST.W       0x6(A0)                         | FOND has style table?
    BEQ.B       SWAPFONT_NO                     | no style table -> integer widths
    LEA.L       0x1C(A0),A0                     | A0 -> FOND style entry table
    MOVE.W      (A0)+,D6                        | D6 = base (plain) extra width
    EXT.L       D6                              | sign-extend to long
    MOVE.B      (FOutUnused).W,D1               | D1 = style mask
    BEQ.B       SWAPFONT_SKIP_4                 | plain text -> skip style sum
    BTST        #0x6,(GotStrike)                | strike already had style?
    BNE.B       FMSWAPFONT_STYLE_INIT           | yes -> use full style mask
    MOVE.W      -0x4A(A6),D0                    | D0 = styles already in strike
    NOT.W       D0                              | invert to "styles missing"
    AND.W       D0,D1                           | apply only missing styles
FMSWAPFONT_STYLE_INIT:
    MOVEQ.L     #0x7,D0                         | D0 = 7 style bits to test
FMSWAPFONT_STYLE_LOOP:
    MOVE.W      (A0)+,D2                        | D2 = next style extra delta
    LSR.W       #0x1,D1                         | shift style bit into C
    BCC.B       FMSWAPFONT_STYLE_NEXT           | bit clear, skip this style
    CMPI.W      #0x8FFF,D2                      | sentinel value (no delta)?
    BGT.B       FMSWAPFONT_STYLE_ADD            | yes -> skip
    BCLR        #0xF,D2                         | clear sign-bit flag
    NEG.W       D2                              | apply as negative delta
FMSWAPFONT_STYLE_ADD:
    EXT.L       D2                              | sign-extend delta to long
    ADD.L       D2,D6                           | accumulate into total extra
FMSWAPFONT_STYLE_NEXT:
    DBF.W       D0,FMSWAPFONT_STYLE_LOOP        | loop 8 style bits
SWAPFONT_SKIP_4:
    ASL.L       #0x4,D6                         | convert to 16.16 fixed (shift << 4)
    SUBQ.W      #0x6,A7                         | reserve 6 bytes for _FixMul/_FixRound
    CLR.W       -(A7)                           | clear high word of result
    BSR.W       WidthTab_DerefPrimary           | A0 = widthTab
    MOVE.W      0x42C(A0),-(A7)                 | push spExtra fixed
    MOVE.L      D6,-(A7)                        | push accumulated extra
    _FixMul                                     | result = spExtra * extra
    MOVE.L      (A7),D6                         | D6 = scaled extra (16.16)
    _FixRound                                   | round to integer
    MOVE.W      (A7)+,D0                        | D0 = rounded extra (signed word)
    MOVE.B      D0,(FOutExtra).W                | store as FOutExtra byte
    TST.B       (FractEnable).W                 | fractional widths enabled?
    BNE.B       FMSWAPFONT_BUILD_WIDTH          | yes -> keep fixed extra in D6
| Called by: FMSWAPFONT_EXTRA_INIT, SWAPFONT_OK_3, FMSWAPFONT_USE_FOND_WIDTHS
SWAPFONT_NO:
    MOVEQ.L     #0x0,D6                         | clear D6 (extra accumulator)
    MOVE.B      (FOutExtra).W,D6                | D6 = signed extra width byte
    EXT.W       D6                              | sign-extend to word
    SWAP.W      D6                              | move to high word (16.16 fixed)
FMSWAPFONT_BUILD_WIDTH:
    BSR.W       WidthTab_DerefPrimary           | A0 = widthTab
    LEA.L       0x404(A0),A1                    | A1 -> +$404 (cached spExtra slot)
    CLR.L       (A1)+                           | clear cached spExtra
    MOVE.L      D6,(A1)                         | store extra width
    ADDA.W      #0x14,A1                        | skip to FOND info area at +$418
    MOVE.W      (FONDID).W,(A1)+                | store FOND ID in cache
    MOVE.L      (LastFOND).W,(A1)               | store FOND handle in cache
    MOVEA.L     (FOutFontHandle).W,A0           | A0 = current font handle
    BSR.W       FMLoadFont_Maybe                | dereference + ensure loaded -> A0=ptr
    MOVEM.W     (A0),D2-D4                      | D2=fontType, D3=firstChar, D4=lastChar
    MOVE.W      D4,D5                           | D5 = lastChar
    SUB.W       D3,D5                           | D5 = char range
    MOVE.W      D5,D1                           | D1 = char range (loop counter)
    ADDQ.W      #0x3,D5                         | +3 for missing char + 2 entries
    ADD.W       D5,D5                           | *2 bytes per offset/width entry
    EXT.L       D5                              | sign-extend to long
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.W      0x10(A0),D0                     | D0 = rowWords
    ADD.L       D0,D0                           | *2 bytes per word
    LEA.L       0x10(A0,D0.L),A1                | A1 = offset/width table in strike
    MOVEQ.L     #0x0,D7                         | D7 = default (missing) char width
    TST.B       (FractEnable).W                 | fractional widths enabled?
    BEQ.B       SWAPFONT_NO_3                   | no -> use integer widths
    BTST        #0x1,D2                         | font has fixed-point widths?
    BNE.B       SWAPFONT_OK_5                   | yes -> use 16-bit widths
    BTST        #0x6,(GotStrike)                | FOND has width table?
    BNE.B       SWAPFONT_NO_3                   | yes -> use those instead
    MOVE.L      A4,D0                           | A4 = FOND width subtable offset
    BEQ.B       SWAPFONT_NO_3                   | no subtable ->
    MOVEA.L     (LastFOND).W,A1                 | get FOND handle
    MOVEA.L     (A1),A1                         | dereference
    ADDA.L      A4,A1                           | A1 -> width subtable in FOND
    BSR.W       WidthTab_DerefPrimary           | A0 = widthTab (for spExtra)
    MOVE.W      0x42C(A0),D0                    | D0 = spExtra fixed
    MOVE.W      -0x4(A1,D5.W),D7                | D7 = missing-char fixed-point width
    MULS.W      D0,D7                           | apply spExtra scaling
    ASL.L       #0x4,D7                         | normalize to 16.16
    BRA.B       SWAPFONT_CONT_3                 | -> apply scaling
| ----------------------------------------------------------
|
| SWAPFONT_NO_3
|
| SWAPFONT_NO_3: get missing symbol width from integer offset/width table
| Called during boot.
SWAPFONT_NO_3:
    MOVE.B      -0x3(A1,D5.W),D7                | D7 = missing char width (8-bit)
    SWAP.W      D7                              | move to high word (16.16 fixed)
    BRA.B       SWAPFONT_CONT_3                 | -> apply scaling
| ----------------------------------------------------------
|
| SWAPFONT_OK_5
|
| SWAPFONT_OK_5: get missing symbol width from 16-bit fixed-point width table
SWAPFONT_OK_5:
    ADDA.L      D5,A1                           | skip past offset table to width table
    MOVE.W      -0x4(A1,D5.W),D7                | D7 = missing char width (16-bit frac)
    ASL.L       #0x8,D7                         | convert 8.8 to 16.16 fixed point
SWAPFONT_CONT_3:
    CMPI.L      #0x10000,(FScaleHFact).W        | scale factor == 1.0?
    SNE.B       D5                              | D5 = $FF if scaling needed
    AND.B       (FScaleDisable).W,D5            | mask with scale-disable flag
    MOVE.L      D7,D0                           | D0 = width to scale
    BSR.B       FMSWAPFONT_SCALE                | apply horizontal scale if needed
    MOVE.L      D0,D7                           | D7 = scaled missing char width
    BSR.W       WidthTab_DerefPrimary           | A0 = widthTab data pointer
    BRA.B       SWAPFONT_LOOP_3                 | -> begin fill loop
SWAPFONT_LOOP_2:
    MOVE.L      D7,(A0)+                        | fill width for chars below firstChar
SWAPFONT_LOOP_3:
    DBF.W       D3,SWAPFONT_LOOP_2              | loop firstChar times
    CLR.B       (UsedFWidth).W                  | flag: not using fractional widths
    TST.B       (FractEnable).W                 | fractional widths enabled?
    BEQ.B       FMSWAPFONT_FILL8_LOOP           | no -> use integer widths at FMSWAPFONT_FILL8_LOOP
    BTST        #0x1,D2                         | font has 16-bit widths?
    BEQ.B       FMSWAPFONT_TRY_FRACTIONAL       | no -> try FOND fractional widths
FMSWAPFONT_FILL16_LOOP:
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.W      (A1)+,D3                        | D3 = 16-bit fixed-point width
    CMPI.W      #0xFFFF,D3                      | missing-char sentinel?
    BNE.B       SWAPFONT_NO_5                   | no, valid width ->
    MOVE.L      D7,D0                           | use default missing char width
    BRA.B       FMSWAPFONT_FILL16_STORE         | -> store it
SWAPFONT_NO_5:
    MOVE.W      D3,D0                           | D0 = 8.8 fixed-point width
    ASL.L       #0x8,D0                         | convert to 16.16 fixed point
    BSR.B       FMSWAPFONT_SCALE                | apply scale + extra (if needed)
FMSWAPFONT_FILL16_STORE:
    MOVE.L      D0,(A0)+                        | store 16.16 fixed-point width
    DBF.W       D1,FMSWAPFONT_FILL16_LOOP       | next char in range
    ST.B        (UsedFWidth).W                  | flag: using fractional widths
    BRA.B       FMSWAPFONT_FILL_TAIL            | -> fill chars above lastChar
FMSWAPFONT_TRY_FRACTIONAL:
    BTST        #0x6,(GotStrike)                | strike already had fractional widths?
    BNE.B       FMSWAPFONT_FILL8_LOOP           | yes -> use integer widths
    MOVE.L      A4,D0                           | A4 = FOND width subtable offset
    BEQ.B       FMSWAPFONT_FILL8_LOOP           | no FOND subtable -> integer widths
    MOVEA.L     (WidthTabHandle).W,A4           | A4 = WidthTabHandle
    MOVEA.L     (A4),A4                         | A4 = widthTab data ptr
    MOVE.W      0x42C(A4),-(A7)                 | push spExtra (point scale factor)
    MOVEA.L     D0,A4                           | A4 = saved width-table pointer
| ----------------------------------------------------------
|
| SWAPFONT_LOOP_6: build width table from 16-bit fixed-point width entries
|
SWAPFONT_LOOP_6:
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.W      (A1)+,D3                        | D3 = FOND width entry (4.12 fixed)
    CMPI.W      #0xFFFF,D3                      | missing-char sentinel?
    BNE.B       SWAPFONT_NO_6                   | no, valid ->
    MOVE.L      D7,D0                           | use default missing char width
    BRA.B       SWAPFONT_CONT_7                 | -> store it
SWAPFONT_NO_6:
    MOVE.W      D3,D0                           | D0 = FOND width
    MULU.W      (A7),D0                         | multiply by point scale factor
    ASL.L       #0x4,D0                         | adjust to 16.16 fixed
    BSR.B       FMSWAPFONT_SCALE                | add extra + scale if needed
SWAPFONT_CONT_7:
    MOVE.L      D0,(A0)+                        | store 16.16 fixed-point width
    DBF.W       D1,SWAPFONT_LOOP_6              | next char in range
    ADDQ.W      #0x2,A7                         | pop scale factor
    ST.B        (UsedFWidth).W                  | flag: using fractional widths
    BRA.B       FMSWAPFONT_FILL_TAIL            | -> fill chars above lastChar
FMSWAPFONT_SCALE:
    TST.L       D0                              | scaling needed?
    BEQ.B       FMSWAPFONT_SCALE_RTS            | width is 0 -> return
    ADD.L       D6,D0                           | add style extra width
    TST.B       D5                              | horizontal scaling needed?
    BEQ.B       FMSWAPFONT_SCALE_RTS            | no -> return
    MOVEM.L     D0-D1/A0-A1,-(A7)               | save regs
    MOVE.L      (FScaleHFact).W,-(A7)           | push horizontal scale factor
    _FixMul                                     | result = D0 * scale
    MOVEM.L     (A7)+,D0/A0-A1                  | restore (D0 = scaled result)
FMSWAPFONT_SCALE_RTS:
    RTS                                         | return scaled width in D0
FMSWAPFONT_FILL8_LOOP:
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.W      (A1)+,D3                        | D3 = offset/width word for this char
    CMPI.W      #0xFFFF,D3                      | missing-char sentinel?
    BNE.B       SWAPFONT_CONT_4                 | valid entry ->
    MOVE.L      D7,D0                           | missing char: use default width
    BRA.B       FMSWAPFONT_FILL8_STORE          | -> store it
SWAPFONT_CONT_4:
    MOVE.B      D3,D0                           | D0.B = char width (low byte)
    SWAP.W      D0                              | move to high word (16.16 fixed)
    BSR.B       FMSWAPFONT_SCALE                | apply scale + extra (if needed)
FMSWAPFONT_FILL8_STORE:
    MOVE.L      D0,(A0)+                        | store 16.16 fixed-point width
    DBF.W       D1,FMSWAPFONT_FILL8_LOOP        | next char in range
FMSWAPFONT_FILL_TAIL:
    MOVE.W      #0xFF,D0                        | 256 entries minus filled chars
    SUB.W       D4,D0                           | D0 = 255 - lastChar
    BRA.B       FMSWAPFONT_FILL_DBF             | -> enter fill loop
FMSWAPFONT_FILL_DEFAULT:
    MOVE.L      D7,(A0)+                        | fill remaining slots with default width
FMSWAPFONT_FILL_DBF:
    DBF.W       D0,FMSWAPFONT_FILL_DEFAULT      | loop until A0 covers all 256 entries
FMSWAPFONT_PUBLISH_EXTRA:
    BSR.W       WidthTab_DerefPrimary           | A0 = widthTab
    LEA.L       0x404(A0),A1                    | A1 -> cached spExtra slot
    MOVE.L      (A1),D7                         | D7 = cached spExtra
    TST.B       (QDExist).W                     | QuickDraw initialized?
    BMI.B       FMSWAPFONT_NO_PORT              | no -> skip QD lookup
    MOVEA.L     (A5),A0                         | A0 -> QD globals
    MOVE.L      (A0),D0                         | D0 = thePort
    BEQ.B       FMSWAPFONT_NO_PORT              | no port set -> skip
    MOVEA.L     D0,A0                           | A0 -> thePort
    MOVE.L      0x4C(A0),D7                     | D7 = current spExtra (16.16 fixed)
FMSWAPFONT_NO_PORT:
    MOVE.L      D7,(LastSPExtra).W              | save spExtra cache
    SUB.L       (A1),D7                         | D7 = delta (new - cached)
    BEQ.B       SWAPFONT_NO_8                   | no change -> skip apply
    ADD.L       D7,(A1)                         | update cached spExtra
    SUBA.W      #0xC,A7                         | reserve _FixRatio chain stack
    MOVE.W      0xA(A3),-(A7)                   | push FMInput.numer.h
    MOVE.W      0xE(A3),-(A7)                   | push FMInput.denom.h
    _FixRatio                                   | FixRatio(numer.h, denom.h)
    SUBQ.W      #0x4,A7                         | space for second ratio
    MOVE.W      (FOutDenom_v).W,-(A7)           | push output denom.v
    MOVE.W      (FOutNumer_v).W,-(A7)           | push output numer.v
    _FixRatio                                   | FixRatio(numer.v, denom.v)
    _FixMul                                     | combine ratios
    MOVE.L      D7,-(A7)                        | push spExtra delta
    _FixMul                                     | delta * combined ratio
    BSR.W       WidthTab_DerefPrimary           | A0 = widthTab data
    MOVE.L      (A7)+,D0                        | D0 = scaled spExtra delta
    ADD.L       D0,0x80(A0)                     | add to space char ($20) width entry
SWAPFONT_NO_8:
    MOVEQ.L     #-0x1,D0                        | init D0 to -1
    MOVE.B      0x6(A3),D0                      | D0 = FMInput.device (driver refNum)
    BEQ.B       FMSWAPFONT_AFTER_CONTROL        | no device driver -> skip notify
    LEA.L       -0x46(A6),A0                    | A0 -> control param block on stack
    MOVE.W      D0,0x18(A0)                     | ioRefNum = device refNum
    MOVE.W      #0x8,0x1A(A0)                   | csCode = 8 (font changed)
    MOVE.L      A3,0x1C(A0)                     | csParam = FMInput pointer
    MOVE.W      0x6(A3),0x20(A0)                | also save device refNum
    _Control                                    | Control(pb) -> driver
FMSWAPFONT_AFTER_CONTROL:
    MOVEA.L     0x8(A6),A3                      | restore A3 = original FMInput
    MOVEA.L     A3,A0                           | A0 = source FMInput
    LEA.L       (CurFMFamily).W,A1              | A1 -> CurFMFamily
    MOVE.L      (A0)+,(A1)+                     | copy FMInput[0..3]
    MOVE.L      (A0)+,(A1)+                     | copy FMInput[4..7]
    MOVE.L      (A0)+,(A1)+                     | copy FMInput[8..b]
    MOVE.L      (A0)+,(A1)+                     | copy FMInput[c..f]
    BSR.W       WidthTab_DerefPrimary           | A0 = widthTab
    CMPI.W      #0xFFFF,0x40C(A0)               | widthTab still tagged invalid?
    BNE.B       FMSWAPFONT_TEAR_DOWN            | already valid -> skip rebuild header
    MOVE.B      (UsedFWidth).W,0x422(A0)        | flag fractional widths used?
    MOVE.B      (FOutUnused).W,0x423(A0)        | save style mask in widthTab
    LEA.L       0x40C(A0),A1                    | A1 -> family/size cache slot
    BSR.W       ResolveFontFamSize              | resolve family/size defaults
    MOVE.L      D0,(A1)+                        | store packed family<<16|size
    ADDQ.W      #0x4,A3                         | skip (family,size) in FMInput
    MOVE.L      (A3)+,(A1)+                     | copy face byte + numer/denom long
    CLR.B       -0x3(A1)                        | clear FMInput.face high byte
    MOVE.L      (A3)+,(A1)+                     | copy denom.h + .v
    MOVE.L      (A3),(A1)                       | copy device byte + extras
FMSWAPFONT_TEAR_DOWN:
    MOVEM.L     (A7)+,D3-D7/A2-A4               | restore saved regs
    MOVE.W      -0x48(A6),D0                    | D0 = saved CurMap
    BEQ.B       FMSWAPFONT_UNLINK               | no save -> skip restore
    MOVE.W      D0,(CurMap).W                   | restore CurMap
FMSWAPFONT_UNLINK:
    UNLK        A6                              | tear down stack frame
    BRA.W       SWAPFONT_EXIT                   | -> RTS at common exit
FMBuildFont:
    SUBA.L      A4,A4                           | A4 = nil (no FOND width subtable yet)
    MOVE.W      0x2(A3),D5                      | D5 = requested point size
    MOVE.W      (A3),D3                         | D3 = FMInput.family
    SUBA.W      #0xE,A7                         | reserve _FixMul/_FixRatio chain stack
    MOVE.W      (FMDotsPerInch_v).W,-(A7)       | push device vertical DPI
    MOVE.W      #0x50,-(A7)                     | push 80 (reference DPI)
    _FixRatio                                   | FixRatio(DPI, 80)
    SUBQ.W      #0x4,A7                         | space for second ratio
    MOVE.W      0xA(A3),-(A7)                   | push FMInput.numer.v
    MOVE.W      0xE(A3),-(A7)                   | push FMInput.denom.v
    _FixRatio                                   | FixRatio(numer.v, denom.v)
    _FixMul                                     | DPI ratio * numer/denom
    CLR.W       -(A7)                           | push 0 (high word of size)
    MOVE.W      D5,-(A7)                        | push requested size
    _FixMul                                     | combined ratio * size
    _FixRound                                   | round to integer
    CMP.W       (FONDID).W,D3                   | family already cached?
    BEQ.B       GETFNAME_OK                     | yes -> reuse cached FOND
    MOVEA.L     (LastFOND).W,A0                 | A0 = LastFOND handle
    MOVE.B      (FondState).W,D0                | D0 = saved FOND state
    _HSetState                                  | restore old FOND lock state
    MOVE.W      D3,D1                           | D1 = family ID for lookup
    MOVE.W      #0xFFFF,(ROMMapInsert).W        | search ROM map first
    BSR.W       SWAPFONT_CONT_27                | look up FOND by family -> A0
    BEQ.B       FMSEARCH_FOND_LOADED            | not found ->
    MOVEA.L     (A0),A1                         | A1 = FOND data ptr
    MOVE.B      (A1),(GotStrike).W              | cache FOND first byte (flags)
    _HGetState                                  | get current FOND lock state
    MOVE.B      D0,(FondState).W                | save in FondState
    _HNoPurge                                   | mark FOND non-purgeable
FMSEARCH_FOND_LOADED:
    CMPI.B      #0xFF,(FontFlag).W              | retry flag set ($FF)?
    BEQ.W       FMSWAPFONT_BAIL_DROP2           | yes -> bail to font-not-found
    MOVE.W      D3,(FONDID).W                   | update FONDID cache
    MOVE.L      A0,(LastFOND).W                 | update LastFOND cache
GETFNAME_OK:
    MOVE.L      (LastFOND).W,D0                 | FOND found?
    BNE.W       FMSEARCHSIZE_ENTRY              | yes -> use FOND-based lookup
    CMPI.W      #0x200,D3                       | family < 512 (old-style FONT)?
    BCS.B       FMSEARCH_AFTER_TRY              | yes -> try old FONT resource
    BRA.W       FMSWAPFONT_BAIL_DROP2           | no -> bail to font-not-found
SWAPFONT_CONT_34:
    ANDI.W      #0xFF80,D3                      | clear size bits, keep family
    OR.W        D0,D3                           | merge in new size
    BSR.W       FMLoadByID                      | try this FONT resource
    BVS.W       FMSWAPFONT_BAIL_DROP4           | overflow -> bail
    RTS                                         | return Z=found
FMSEARCH_AFTER_TRY:
    MOVE.W      (A7)+,D0                        | D0 = scaled point size
    BNE.B       FMSEARCH_NORMALIZE_SIZE         | nonzero ->
    MOVEQ.L     #0x1,D0                         | clamp to size 1
FMSEARCH_NORMALIZE_SIZE:
    ANDI.W      #0x7F,D0                        | mask to 7 bits (FONT size field)
    ASL.W       #0x7,D3                         | shift family to FONT ID high bits
    OR.W        D0,D3                           | D3 = FONT resource ID
    MOVE.W      D0,D7                           | D7 = save requested size
    BSR.W       FMLoadByID                      | try exact size FONT resource
    BVS.W       FMSWAPFONT_RETRY_TAIL           | overflow -> bail
    BNE.B       SWAPFONT_FOUND_3                | found -> use it
    MOVE.W      D3,D4                           | D4 = save font ID
    MOVE.W      D7,D0                           | D0 = requested size
    CMPI.W      #0x40,D0                        | size >= 64?
    BGE.B       SWAPFONT_SKIP_6                 | yes, skip double (overflow)
    ADD.W       D0,D0                           | try double size
    BSR.B       SWAPFONT_CONT_34                | look up FONT at 2x size
    BNE.B       SWAPFONT_FOUND_3                | found -> use (will scale down)
SWAPFONT_SKIP_6:
    MOVE.W      D7,D0                           | D0 = requested size
    LSR.W       #0x1,D0                         | try half size
    BCS.B       SWAPFONT_CONT_35                | odd size -> can't halve evenly
    BSR.B       SWAPFONT_CONT_34                | look up FONT at half size
    BNE.B       SWAPFONT_FOUND_3                | found -> use (will scale up)
| SWAPFONT_CONT_35: exact/double/half not found - search adjacent sizes
SWAPFONT_CONT_35:
    MOVE.W      D4,D3                           | restore original font ID
    MOVEQ.L     #0x1,D6                         | D6 = search step (+1)
    TST.B       (FScaleDisable).W               | scaling disabled?
    BEQ.B       SWAPFONT_NEXT_3                 | no -> search upward first
    MOVEQ.L     #-0x1,D6                        | search downward first (prefer smaller)
SWAPFONT_NEXT_3:
    ADD.W       D6,D3                           | try next adjacent size
    ANDI.W      #0x7F,D3                        | mask size field
    BEQ.W       SWAPFONT_CONT_38                | wrapped to 0 -> exhausted search
    MOVE.W      D4,D0                           | D0 = original family bits
    ANDI.W      #0xFF80,D0                      | keep family, clear size
    OR.W        D0,D3                           | combine family + new size
    BSR.W       FMLoadByID                      | try this FONT resource
    BVS.W       FMSWAPFONT_RETRY_TAIL           | overflow -> bail
    BEQ.B       SWAPFONT_NEXT_3                 | not found -> try next size
SWAPFONT_FOUND_3:
    MOVE.L      A0,(FOutFontHandle).W           | save font handle
    BSR.W       BUILDBBOX_BODY                  | build glyph bounding box table
    SUBQ.W      #0x4,A7                         | space for FixRatio result
    MOVE.W      0x2(A3),-(A7)                   | push requested size
    MOVE.W      D3,-(A7)                        | push actual FONT resource size
    ANDI.W      #0x7F,(A7)                      | mask to 7-bit size field
    _FixRatio                                   | FixRatio(requested, actual)
    MOVE.L      (A7)+,D6                        | D6 = size ratio (16.16 fixed)
    BSR.W       WidthTab_DerefPrimary           | A0 = widthTab
    MOVE.W      D3,0x42C(A0)                    | store FONT ID for width scaling
    MOVE.L      (FOutFontHandle).W,0x400(A0)    | cache font handle in widthTab
    MOVEQ.L     #0x0,D5                         | D5 = 0 (horizontal first)
    BSR.B       SWAPFONT_CONT_36                | compute horizontal scale
    MOVEQ.L     #0x2,D5                         | D5 = 2 (vertical)
SWAPFONT_CONT_36:
    SUBA.W      #0xC,A7                         | reserve _FixMul chain stack
    MOVE.W      0x8(A3,D5.W),-(A7)              | push FMInput.numer (h or v)
    MOVE.W      0xC(A3,D5.W),-(A7)              | push FMInput.denom (h or v)
    _FixRatio                                   | FixRatio(numer, denom)
    SUBQ.W      #0x4,A7                         | space for DPI ratio
    LEA.L       (FMDotsPerInch_h).W,A0          | A0 -> device DPI array
    MOVE.W      0x0(A0,D5.W),-(A7)              | push device DPI (h or v)
    MOVE.W      #0x50,-(A7)                     | push 80 (reference DPI)
    _FixRatio                                   | FixRatio(DPI, 80)
    _FixMul                                     | numer/denom * DPI/80
    MOVE.L      D6,-(A7)                        | push size ratio
    _FixMul                                     | combined * size ratio
    LEA.L       (FOutNumer_h).W,A0              | A0 -> output numer/denom array
    MOVE.L      (A7)+,D0                        | D0 = combined scale (16.16)
    LSR.L       #0x8,D0                         | convert to 8.8 for numer
    MOVE.W      D0,0x0(A0,D5.W)                 | store numer (h or v)
    MOVE.W      #0x100,0x4(A0,D5.W)             | denom = 256 (1.0 in 8.8)
    MOVE.L      FPOINTONE(PC),D1                | D1 = 1.0 fixed-point default
    TST.B       (FScaleDisable).W               | scaling enabled?
    BEQ.B       FMSCALE_STORE_NUMER             | no -> use 1:1 scale factor
    MOVEQ.L     #0x0,D1                         | clear D1
    MOVE.W      D0,D1                           | D1 = scale value (8.8)
    MOVE.W      #0x100,D0                       | D0 = denom (starts at 256)
SWAPFONT_CONT_37:
    CMPI.W      #0x200,D1                       | numer >= 512?
    BCS.B       SWAPFONT_NO_18                  | no, in range ->
    ASL.W       #0x1,D0                         | double denom
    ASR.W       #0x1,D1                         | halve numer
    BRA.B       SWAPFONT_CONT_37                | recheck
SWAPFONT_NO_18:
    CMPI.W      #0xC0,D1                        | numer < 192?
    BCC.B       SWAPFONT_NO_19                  | no, in range ->
    ASR.W       #0x1,D0                         | halve denom
    ASL.W       #0x1,D1                         | double numer
    BRA.B       SWAPFONT_NO_18                  | recheck
SWAPFONT_NO_19:
    CMPI.W      #0x100,D1                       | numer >= 256 (1.0)?
    BCC.B       SWAPFONT_OK_12                  | yes, well-normalized ->
    MOVE.W      D0,D2                           | D2 = denom
    ADD.W       D0,D0                           | D0 = 2*denom
    ADD.W       D2,D0                           | D0 = 3*denom
    ASR.W       #0x2,D0                         | D0 = 3*denom/4
    ASL.W       #0x2,D1                         | numer *= 4
    DIVU.W      #0x3,D1                         | numer = 4*numer/3
    EXT.L       D1                              | clear remainder
SWAPFONT_OK_12:
    MOVE.W      D0,0x0(A0,D5.W)                 | store normalized numer
    ASL.L       #0x8,D1                         | convert to 16.16 fixed point
FMSCALE_STORE_NUMER:
    TST.W       D5                              | horizontal axis?
    BEQ.B       FMSCALE_STORE_VFACT             | yes -> store H factor
    MOVE.L      D1,(FScaleHFact).W              | update horizontal scale factor
    BRA.B       FMSCALE_AFTER_STORE             | -> common tail
FMSCALE_STORE_VFACT:
    MOVE.L      D1,(FScaleVFact).W              | update vertical scale factor
FMSCALE_AFTER_STORE:
    MOVEA.L     (WidthTabHandle).W,A1           | A1 = WidthTabHandle
    MOVEA.L     (A1),A1                         | A1 = widthTab data ptr
    LEA.L       0x424(A1),A1                    | A1 -> cached numer/denom array
    MOVE.W      D0,0x0(A1,D5.W)                 | store numer in width table cache
    ASR.L       #0x8,D1                         | back to 8.8 fixed
    MOVE.W      D1,0x4(A1,D5.W)                 | store denom in width table cache
    RTS                                         | return scaled values stored
SWAPFONT_CONT_38:
    TST.B       (FScaleDisable).W               | scaling disabled?
    BEQ.B       SWAPFONT_NO_22                  | no -> try opposite direction
    NEG.W       D6                              | flip search step
    BMI.B       FMSWAPFONT_RETRY_TAIL           | already negative -> exhausted
    BRA.B       SWAPFONT_OK_14                  | -> retry with new step
SWAPFONT_NO_22:
    NEG.W       D6                              | flip search step
    BPL.B       FMSWAPFONT_RETRY_TAIL           | now positive -> exhausted
SWAPFONT_OK_14:
    MOVE.W      D4,D3                           | restore original font ID
    BRA.W       SWAPFONT_NEXT_3                 | -> resume size search
FMSWAPFONT_BAIL_DROP4:
    ADDQ.W      #0x2,A7                         | balance pushed CLR.W -(A7)
FMSWAPFONT_BAIL_DROP2:
    ADDQ.W      #0x2,A7                         | balance pushed size word
| Called by: FMSWAPFONT_ABORT, FMSEARCH_NORMALIZE_SIZE, SWAPFONT_NEXT_3, SWAPFONT_CONT_38, SWAPFONT_NO_22 (and 2 more)
FMSWAPFONT_RETRY_TAIL:
    ADDQ.W      #0x4,A7                         | balance pushed args
    MOVE.W      (A3),D3                         | D3 = original FMInput.family
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.B      (FontFlag).W,D0                 | D0 = retry-stage counter
    BPL.B       FMSWAPFONT_NEXT_STAGE           | not exhausted -> dispatch retry
    BSR.W       WidthTab_InvalidateAll          | exhausted -> use system font default
    CLR.B       (FontFlag).W                    | clear retry counter
    BRA.B       FMSWAPFONT_FINISH               | -> finalize FMInput
FMSWAPFONT_NEXT_STAGE:
    ADDQ.B      #0x2,(FontFlag).W               | advance retry stage by 2 (table stride)
    MOVE.W      FMSWAPFONT_RETRY_TBL(PC,D0.W),D0 | D0 = relative offset from table
    JSR         FMSWAPFONT_RETRY_TBL(PC,D0.W)   | dispatch retry strategy
FMSWAPFONT_FINISH:
    MOVEA.L     0x8(A6),A1                      | A1 = original caller FMInput
    MOVE.W      D3,(A3)                         | overwrite family with retry choice
    MOVE.W      0x2(A1),0x2(A3)                 | restore caller-requested size
    BRA.W       FMSWAPFONT_DEVICE_OK            | -> retry FMSwapFont with new family
| ----------------------------------------------------------
| FMSWAPFONT_RETRY_TBL: PC-relative dispatch table for FMSwapFont retry stages.
| Stages indexed by (FontFlag) value: each 2-byte entry holds the
| relative offset to the corresponding ENTRY_19A3* handler.
FMSWAPFONT_RETRY_TBL:
    .short      0x000A                          | stage 0 -> FMSWAPFONT_TRY_APFONT (try ApFontID)
    .long       0x00300040                      | stages 1-2 -> 0x30, 0x40 offsets
    .long       0x00580058                      | stages 3-4 -> 0x58, 0x58 offsets
FMSWAPFONT_TRY_APFONT:
    MOVE.W      (ApFontID).W,D1                 | D1 = application font family
FMSWAPFONT_BLOCK_CMP:
    MOVEQ.L     #0x9,D2                         | D2 = 9 (size-bits shift)
    LSR.W       D2,D1                           | D1 = ApFontID family bits
    SUBI.W      #0x1F,D1                        | normalize to FOND-block index
    BPL.B       FMSWAPFONT_NORM_CURFAM          | nonneg ->
    MOVEQ.L     #0x0,D1                         | clamp to 0
FMSWAPFONT_NORM_CURFAM:
    MOVE.W      D3,D0                           | D0 = current family
    LSR.W       D2,D0                           | D0 = current family block index
    SUBI.W      #0x1F,D0                        | normalize
    BPL.B       FMSWAPFONT_SAME_BLOCK           | nonneg ->
    MOVEQ.L     #0x0,D0                         | clamp to 0
FMSWAPFONT_SAME_BLOCK:
    CMP.W       D0,D1                           | same FOND block as current?
    BNE.B       FMSWAPFONT_RETRY_TAIL           | no -> retry with ApFontID
    MOVE.W      (ApFontID).W,D3                 | yes -> set D3 = ApFontID
    RTS                                         | return new family in D3
SWAPFONT_NO_26:
    CMPI.W      #0x4000,D3                      | family in old-style FONT range?
    BCS.B       FMSWAPFONT_USE_GENEVA           | yes -> use Geneva (3)
    ANDI.W      #0xFE00,D3                      | clear size bits, keep family block
    RTS                                         | return cleaned family in D3
FMSWAPFONT_USE_GENEVA:
    MOVEQ.L     #0x3,D3                         | D3 = Geneva (family 3)
    RTS                                         | return Geneva
FMSWAPFONT_TRY_SYSFONT:
    MOVE.W      (SysFontFam).W,D1               | D1 = system font family
    BRA.B       FMSWAPFONT_BLOCK_CMP            | -> compare blocks, retry if needed
FMSWAPFONT_SYSMAP_ENTRY:
    LINK        A6,#-0x4A                       | allocate FMSwapFont stack frame
    MOVEM.L     D3-D7/A2-A4,-(A7)               | save callee-saved regs
    MOVEA.L     0x8(A6),A3                      | A3 = caller FMInput
    BSR.B       FMSWAPFONT_FORCE_SYSMAP         | switch to system map, clear D3
    BRA.W       FMSWAPFONT_NORMALIZE            | -> resume FMSwapFont body
FMSWAPFONT_FORCE_SYSMAP:
    MOVE.W      (CurMap).W,-0x48(A6)            | save CurMap in frame
    MOVE.W      (SysMap).W,(CurMap).W           | force system map for system fonts
    MOVEQ.L     #0x0,D3                         | D3 = 0 (system family)
    RTS                                         | return with map switched
| ----------------------------------------------------------
|
| SWAPFONT_CONT_39
|
| SWAPFONT_CONT_39: query device driver for its DPI resolution
| D0 = device (0=screen, nonzero=printer driver refNum)
| Fills FMDotsPerInch_h/v with device resolution
SWAPFONT_CONT_39:
    TST.W       D0                              | screen device?
    BEQ.B       SWAPFONT_OK_16                  | yes -> use default DPI
    MOVEQ.L     #-0x1,D0                        | init D0 for sign-extend
    MOVE.B      0x6(A3),D0                      | D0 = device driver refNum
    MOVEQ.L     #0x32,D1                        | 50 bytes for param block
    SUBA.L      D1,A7                           | allocate param block on stack
    LEA.L       0x18(A7),A0                     | A0 -> csParam area
    MOVE.W      D0,(A0)+                        | ioRefNum = driver refNum
    MOVE.W      #0x8,(A0)+                      | csCode = 8 (get resolution)
    LEA.L       (FMDotsPerInch_h).W,A1          | A1 -> dest for DPI values
    MOVE.L      A1,(A0)+                        | csParam[0] = ptr to DPI buffer
    MOVE.W      0x6(A3),(A0)+                   | csParam[2] = device ID
    MOVEA.L     A7,A0                           | A0 = param block
    _Status                                     | query driver for DPI
    ADDA.L      D1,A7                           | pop param block
    RTS                                         | return DPI in FMDotsPerInch_h/v
SWAPFONT_OK_16:
    LEA.L       (FMDotsPerInch_h).W,A1          | A1 -> Font Manager globals dest
    LEA.L       SWAPFONT_CONT_45(PC),A0         | A0 -> default Font Manager params
    MOVEQ.L     #0x1C,D0                        | length: 28 bytes
    _BlockMove                                  | initialize Font Manager globals
    RTS                                         | return defaults loaded
FMSEARCH_GOT_ALTID:
    MOVE.L      (A0),D0                         | D0.hi = style, D0.lo = resource ID
    MOVE.L      D0,-0x14(A6)                    | save (style,id) for later
FMLoadByID_AltMap:
    MOVE.W      D0,-(A7)                        | save resource ID on stack
    SUBQ.W      #0x4,A7                         | space for GetResource result
    MOVE.L      #0x4E464E54,-(A7)               | push 'NFNT' resource type
    MOVE.W      D0,-(A7)                        | push resource ID
    MOVE.W      #0xFFFF,(ROMMapInsert).W        | include ROM map
    _GetResource                                | try loading NFNT
    MOVE.L      (A7)+,D0                        | D0 = NFNT handle
    BEQ.B       FMLoadByID_AllMaps              | not found -> try FONT fallback
    ADDQ.W      #0x2,A7                         | pop saved ID (not needed)
    BRA.B       FMLoadByID_AfterGet             | -> set CCR + return handle
SWAPFONT_CONT_26:
    MOVE.W      #0xFF00,(ROMMapInsert).W        | search ROM map then app map
    MOVE.W      D1,-(A7)                        | push alt resource ID
    BRA.B       FMLoadByID_DoGet                | -> common GetResource path
FMLoadByID:
    MOVE.W      D3,-(A7)                        | push current FONT ID
FMLoadByID_AllMaps:
    MOVE.W      #0xFFFF,(ROMMapInsert).W        | include ROM map
FMLoadByID_DoGet:
    MOVE.W      (A7)+,D0                        | D0 = saved resource ID
    SUBQ.W      #0x4,A7                         | space for GetResource result
    MOVE.L      #0x464F4E54,-(A7)               | push 'FONT' resource type
    MOVE.W      D0,-(A7)                        | push resource ID
    _GetResource                                | try loading FONT
    MOVE.L      (A7)+,D0                        | D0 = FONT handle (or nil)
FMLoadByID_AfterGet:
    MOVEA.L     D0,A0                           | A0 = font handle (for return)
    SEQ.B       D0                              | D0 = $FF if not found
    ANDI.W      #0x4,D0                         | mask to Z bit position
    CMPI.B      #0xFF,(FontFlag).W              | first-time search?
    BNE.B       FMLoadByID_RTS                  | no -> just set Z
    BSET        #0x1,D0                         | also signal V bit (failure)
FMLoadByID_RTS:
    MOVE.W      D0,CCR                          | propagate Z/V to caller
    RTS                                         | return font handle in A0
FMSearchFOND_BySize:
    MOVEA.L     (A2),A0                         | A0 = FOND data ptr
    LEA.L       0x34(A0),A0                     | A0 -> font association table
    MOVE.W      (A0)+,D1                        | D1 = entry count - 1
SWAPFONT_LOOP_10:
    CMP.W       (A0)+,D3                        | compare requested size with entry
    BEQ.B       FMSEARCH_GOT_ALTID              | exact match -> load NFNT/FONT
    BLT.B       FMSearchFOND_NotFound           | requested < entry -> not found
    ADDQ.W      #0x4,A0                         | skip style+resID fields
    DBF.W       D1,SWAPFONT_LOOP_10             | next entry
FMSearchFOND_NotFound:
    MOVEQ.L     #0x0,D0                         | return D0 = 0 (not found)
    RTS                                         | return from SWAPFONT_CONT_39
FMSEARCHSIZE_ENTRY:
    MOVE.W      (A7)+,D5                        | D5 = scaled point size
    MOVEA.L     D0,A2                           | A2 = FOND handle
    MOVE.W      D5,D3                           | D3 = size to search for
    BSR.B       FMSearchFOND_BySize             | look up exact size in FOND
    BVS.B       FMSEARCHSIZE_RETRY              | overflow -> bail
    BNE.B       FMSEARCHSIZE_AFTER_LOOKUP       | found ->
    TST.B       (FScaleDisable).W               | scaling disabled?
    BNE.B       SWAPFONT_SKIP_7                 | yes -> skip size variants
    ADD.W       D3,D3                           | try double size
    BSR.B       FMSearchFOND_BySize             | look up in FOND
    BVS.B       FMSEARCHSIZE_RETRY              | overflow -> bail
    BNE.B       FMSEARCHSIZE_AFTER_LOOKUP       | found ->
    MOVE.W      D5,D3                           | restore original size
    LSR.W       #0x1,D3                         | try half size
    BCS.B       SWAPFONT_SKIP_7                 | odd -> can't halve evenly
    BSR.B       FMSearchFOND_BySize             | look up in FOND
    BVS.B       FMSEARCHSIZE_RETRY              | overflow -> bail
FMSEARCHSIZE_AFTER_LOOKUP:
    BNE.B       FMSEARCHSIZE_FOUND              | found -> style matching
| SWAPFONT_SKIP_7: no exact/double/half - find closest available size in FOND
SWAPFONT_SKIP_7:
    MOVEA.L     (A2),A0                         | A0 = FOND data ptr
    LEA.L       0x34(A0),A0                     | A0 -> font association table
    MOVE.W      (A0)+,D4                        | D4 = entry count - 1
    MOVEQ.L     #0x0,D1                         | D1 = best matching size (0=none)
    MOVEQ.L     #0x7F,D2                        | D2 = smallest distance so far
SWAPFONT_LOOP_11:
    MOVE.W      D5,D0                           | D0 = requested size
    SUB.W       (A0),D0                         | D0 = delta (requested - available)
    BPL.B       SWAPFONT_CONT_42                | positive delta ->
    TST.B       (FScaleDisable).W               | scaling disabled?
    BEQ.B       SWAPFONT_NO_23                  | no ->
    TST.W       D1                              | already have a candidate?
    BNE.B       SWAPFONT_OK_17                  | yes, prefer smaller -> stop search
SWAPFONT_NO_23:
    NEG.W       D0                              | make delta positive
SWAPFONT_CONT_42:
    CMP.W       D2,D0                           | closer than best so far?
    BGT.B       SWAPFONT_NO_24                  | no ->
    MOVE.W      D0,D2                           | update best distance
    MOVE.W      (A0),D1                         | update best matching size
SWAPFONT_NO_24:
    ADDQ.W      #0x6,A0                         | next entry (6 bytes per entry)
    DBF.W       D4,SWAPFONT_LOOP_11             | loop all entries
SWAPFONT_OK_17:
    MOVE.W      D1,D3                           | D3 = best available size
    BSR.B       FMSearchFOND_BySize             | look up in association table
    BVS.B       FMSEARCHSIZE_RETRY              | overflow -> bail
    BEQ.B       FMSEARCHSIZE_RETRY              | not found -> bail to retry
FMSEARCHSIZE_FOUND:
    MOVE.L      A0,D0                           | save font handle in D0
    MOVEA.L     (A2),A0                         | A0 = FOND data ptr
    LEA.L       0x34(A0),A0                     | A0 -> font association table
    MOVE.W      (A0)+,D1                        | D1 = entry count - 1
SWAPFONT_LOOP_12:
    CMP.W       (A0),D3                         | this entry matches size D3?
    BEQ.B       FMSTYLE_SCAN_INIT               | yes -> check style
    ADDQ.W      #0x6,A0                         | skip to next entry
    DBF.W       D1,SWAPFONT_LOOP_12             | loop
| Called by: FMSEARCHSIZE_ENTRY, SWAPFONT_OK_17, FMSTYLE_LOAD_BEST
FMSEARCHSIZE_RETRY:
    BRA.W       FMSWAPFONT_RETRY_TAIL           | -> bail to font-search retry
| ----------------------------------------------------------
| SWAPFONT_CONT_44: per-style match weight table indexed by style bit (D7).
| Used to score how well a FOND entry matches the requested style mask:
|   bit 0 (bold)        weight 0
|   bit 1 (italic)      weight 1
|   bit 2 (underline)   weight 2
|   bit 3 (outline)     weight 3
|   bit 4 (shadow)      weight 1
|   bit 5 (condense)    weight 8 (heavily preferred)
|   bit 6 (extend)      weight 4
|   bit 7 (reserved)    weight 0
SWAPFONT_CONT_44:
    .long       0x04080103                      | weights[7..4]: 4,8,1,3
    .long       0x03020100                      | weights[3..0]: 3,2,1,0
| FMSTYLE_SCAN_INIT - called from 1 place

FMSTYLE_SCAN_INIT:
    MOVEQ.L     #0x0,D2                         | clear D2
    ADDQ.W      #0x2,A0                         | skip past size field to style
    MOVEQ.L     #-0x2,D4                        | D4 = best style match score (init -2)
    MOVE.B      0x4(A3),D2                      | D2 = requested style bits (face)
FMSTYLE_SCAN_LOOP:
    MOVE.W      (A0),D6                         | D6 = this entry's style word
    CMP.W       D6,D2                           | exact style match?
    BNE.B       FMSTYLE_NOT_EXACT               | no ->
    MOVEA.L     A0,A1                           | A1 = matching entry
    BRA.B       FMSTYLE_LOAD_BEST               | -> load font from this entry
FMSTYLE_NOT_EXACT:
    MOVEQ.L     #-0x1,D5                        | D5 = score (init -1 = bad)
    MOVE.W      D2,D7                           | D7 = requested styles
    NOT.W       D7                              | D7 = complement
    AND.W       D6,D7                           | D7 = entry styles not in request
    BNE.B       FMSTYLE_KEEP_BEST               | has extra styles -> skip
    MOVEQ.L     #0x0,D5                         | D5 = match score (start at 0)
    MOVEQ.L     #0x7,D7                         | 8 style bits to check
    AND.W       D2,D6                           | D6 = matched styles only
FMSTYLE_BIT_LOOP:
    ASL.B       #0x1,D6                         | shift next style bit out
    BCC.B       FMSTYLE_BIT_NEXT                | bit clear -> skip add
    ADD.B       SWAPFONT_CONT_44(PC,D7.W),D5    | add weighted score for this style
FMSTYLE_BIT_NEXT:
    DBF.W       D7,FMSTYLE_BIT_LOOP             | next style bit
FMSTYLE_KEEP_BEST:
    CMP.W       D5,D4                           | better than best so far?
    BGE.B       SWAPFONT_SKIP_9                 | no ->
    MOVE.W      D5,D4                           | update best score
    MOVEA.L     A0,A1                           | A1 = best matching entry
SWAPFONT_SKIP_9:
    ADDQ.W      #0x4,A0                         | skip resource ID, advance to next
    CMP.W       (A0)+,D3                        | still same size?
    DBNE.W      D1,FMSTYLE_SCAN_LOOP            | yes -> check next style variant
FMSTYLE_LOAD_BEST:
    MOVE.W      (A1)+,D6                        | D6 = style bits of matched entry
    MOVE.W      -0x12(A6),D1                    | D1 = resource ID from earlier match
    CMP.W       (A1),D1                         | same resource ID?
    MOVEA.L     D0,A0                           | A0 = font handle
    BEQ.B       FMSTYLE_LOADED                  | yes, already loaded ->
    MOVE.L      A0,D4                           | save A0
    MOVE.W      (A1),D0                         | D0 = resource ID from FOND entry
    BSR.W       FMLoadByID_AltMap               | load NFNT/FONT resource
    BVS.B       FMSEARCHSIZE_RETRY              | overflow -> bail
    BNE.B       FMSTYLE_LOADED                  | loaded OK ->
    MOVEA.L     D4,A0                           | restore A0 (load failed)
    MOVE.W      -0x14(A6),D6                    | use previously saved style
FMSTYLE_LOADED:
    NOT.W       D6                              | complement: bits NOT provided by font
    AND.B       D6,(FOutUnused).W               | clear provided styles from request
    MOVEA.L     (A2),A1                         | A1 = FOND data ptr
    MOVE.W      0x6(A1),D1                      | D1 = FOND lastChar
    BEQ.B       FMSTYLE_DONE                    | no width subtable ->
    CLR.W       -0x4A(A6)                       | clear "missing styles" cache
    SUB.W       0x4(A1),D1                      | D1 = char range
    ADDQ.W      #0x4,D1                         | + missing + 2 entries (4 = +3 +1)
    ADD.W       D1,D1                           | * 2 bytes per entry = row size
    MOVE.L      0x10(A1),D0                     | D0 = offset to width subtable
    BEQ.B       FMSTYLE_DONE                    | no width subtable ->
    ADDA.L      D0,A1                           | A1 -> width subtable header
    MOVE.W      (A1)+,D2                        | D2 = number of style entries - 1
    BMI.B       FMSTYLE_DONE                    | negative -> no entries
    MOVEQ.L     #-0x1,D4                        | D4 = best score so far (init -1)
    MOVEQ.L     #0x0,D0                         | clear D0
FMSTYLE_SCAN_NEXT:
    MOVE.B      0x4(A3),D0                      | D0 = requested style mask
    CMP.W       (A1),D0                         | exact style match?
    BEQ.B       FMSTYLE_SAVE_BEST               | yes -> use this width subtable
    NOT.W       D0                              | invert request
    AND.W       (A1),D0                         | D0 = entry styles not in request
    BNE.B       FMSTYLE_SCORE_ADV               | has extra styles -> skip
    MOVEQ.L     #0x0,D5                         | D5 = match score
    MOVE.B      0x4(A3),D0                      | D0 = requested style
    AND.W       (A1),D0                         | mask to matched styles
    MOVEQ.L     #0x7,D7                         | 8 style bits to test
FMSTYLE_SCORE_LOOP:
    ASL.B       #0x1,D0                         | shift next style bit out
    BCC.B       FMSTYLE_SCORE_NEXT              | bit clear -> skip add
    ADD.B       FMSTYLE_WEIGHT_TBL(PC,D7.W),D5  | add weighted score
FMSTYLE_SCORE_NEXT:
    DBF.W       D7,FMSTYLE_SCORE_LOOP           | next style bit
    CMP.W       D5,D4                           | better than best?
    BGE.B       FMSTYLE_SCORE_ADV               | no ->
    MOVE.W      D5,D4                           | update best score
    MOVE.L      A1,D6                           | save best entry pointer
FMSTYLE_SCORE_ADV:
    ADDA.W      D1,A1                           | skip width data (row size bytes)
    DBF.W       D2,FMSTYLE_SCAN_NEXT            | next style entry
    TST.W       D4                              | found any acceptable match?
    BEQ.B       FMSTYLE_DONE                    | no -> skip
    MOVEA.L     D6,A1                           | A1 = best matching entry
FMSTYLE_SAVE_BEST:
    MOVE.W      (A1)+,-0x4A(A6)                 | save matched style mask in frame
    SUBA.L      (A2),A1                         | A1 = offset from FOND start
    MOVEA.L     A1,A4                           | A4 = width subtable offset for later
FMSTYLE_DONE:
    BRA.W       SWAPFONT_FOUND_3                | -> finish with font metrics
| ----------------------------------------------------------
| FMSTYLE_WEIGHT_TBL: per-style match weight table (2nd copy, used at FMSTYLE_SCORE_LOOP).
| Same purpose as SWAPFONT_CONT_44 but with different weights:
|   bit 0 (bold)        weight 4
|   bit 1 (italic)      weight 2
|   bit 2 (underline)   weight 2
|   bit 3 (outline)     weight 0
|   bit 4 (shadow)      weight 4
|   bit 5 (condense)    weight 5
|   bit 6 (extend)      weight 3
|   bit 7 (reserved)    weight 1
FMSTYLE_WEIGHT_TBL:
    .long       0x01030504                      | weights[7..4]: 1,3,5,4
    .long       0x04020200                      | weights[3..0]: 4,2,2,0
| ----------------------------------------------------------
| FPOINTONE: 16.16 fixed-point constant 1.0 (0x00010000).
FPOINTONE:
    .long       0x00010000                      | 1.0 in 16.16 fixed point
| ----------------------------------------------------------
| SWAPFONT_CONT_45: 28-byte block of default Font Manager parameters
| copied to FMDotsPerInch_h via _BlockMove on screen-only path:
|   +$00..$03  default DPI (h=80, v=80)
|   +$04..$1B  FMStyleTab style-modification table (bold/italic/under/
|              outline/shadow/condense/extend offsets, extras, UL params)
| Followed by the standard Mac arrow cursor: 32 bytes mask + 32 bytes
| data + 4 bytes hotspot (rendered/used at runtime by other code).
SWAPFONT_CONT_45:
    .long       0x00500050
    .long       0x00010101
    .long       0x08000000
    .long       0x00050101
    .long       0x05020200
    .long       0x00FF0000
    .long       0x01010101
    .long       0x00777A3B
    .long       0xC9353019
    .long       0x80AF3018
    .long       0x7A601809
    .long       0x00603198
    .long       0x09727BBA
    .long       0x49BFE09D
    .long       0x010220BF
    .long       0x408801F1
    .long       0xFE020A81
    .long       0xBC040703
    .long       0x9A08040F
    .long       0x80991FC0
    .long       0x3760B90F
    .long       0x0403DF0F
    .long       0x98083760
    .long       0x1FC1A804
    .long       0x0F800202
    .long       0x9A010487
    .short      0x0818
| _GetFName ($A8FF): get font name from font number
| Pascal: procedure GetFName(familyID: INTEGER; VAR name: Str255);
GETFONTNAME:
    MOVEA.L     (A7)+,A1                        | A1 = return address
    MOVE.L      (A7)+,D2                        | D2 = name buffer ptr (Str255)
    MOVE.W      (A7)+,D1                        | D1 = familyID
    MOVE.W      #0xFF00,(ROMMapInsert).W        | include ROM resources
    BSR.B       FMResolveFamily                 | look up FOND by family ID
    BNE.B       GETFONTNAME_GOT_RES             | found FOND ->
    CMPI.W      #0x200,D1                       | familyID >= 512?
    BCC.B       GETFONTNAME_NONE                | yes -> empty name
    ASL.W       #0x7,D1                         | convert family to FONT resource ID
    BSR.W       SWAPFONT_CONT_26                | load FONT resource
    BEQ.B       GETFONTNAME_NONE                | not found -> empty name
GETFONTNAME_GOT_RES:
    MOVE.L      A0,-(A7)                        | push resource handle
    CLR.L       -(A7)                           | push ptr for resType (discarded)
    CLR.L       -(A7)                           | push ptr for resID (discarded)
    MOVE.L      D2,-(A7)                        | push caller's name buffer
    MOVE.W      #0xFF00,(ROMMapInsert).W        | include ROM
    _GetResInfo                                 | fetch resource name into buffer
    BRA.B       GETFONTNAME_RTS                 | -> return via JMP (A1)
GETFONTNAME_NONE:
    MOVEA.L     D2,A0                           | A0 = caller's name buffer
    CLR.B       (A0)                            | empty Str255 (length 0)
GETFONTNAME_RTS:
    JMP         (A1)                            | tail-call return from GETFONTNAME_RTS via A1
| ----------------------------------------------------------
| FMResolveFamily: look up FOND for D1 with system/app substitution.
| D1 = 0 -> SysFontFam, D1 = 1 -> ApFontID, otherwise use D1 as-is.
FMResolveFamily:
    TST.W       D1                              | family 0 (system)?
    BNE.B       FMResolveFamily_NotSys          | no ->
    MOVE.W      (SysFontFam).W,D1               | substitute system font family
    BRA.B       SWAPFONT_CONT_27                | -> load FOND
FMResolveFamily_NotSys:
    CMPI.W      #0x1,D1                         | family 1 (application)?
    BNE.B       SWAPFONT_CONT_27                | no ->
    MOVE.W      (ApFontID).W,D1                 | substitute app font family
| Called by: FMResolveFamily, GETFONTNAME, REALFONT (and other Font Mgr code)
SWAPFONT_CONT_27:
    SUBQ.W      #0x4,A7                         | space for handle result
    MOVE.L      #0x464F4E44,-(A7)               | push 'FOND' resource type
    MOVE.W      D1,-(A7)                        | push family ID as resource ID
    _GetResource                                | load FOND resource
    MOVE.L      (A7)+,D0                        | D0 = FOND handle (or nil)
    MOVEA.L     D0,A0                           | A0 = handle for caller
    RTS                                         | return Z=found
| _RealFont ($A902): is point size available as physical font?
| Pascal: function RealFont(fontNum: INTEGER; size: INTEGER): BOOLEAN;
REALFONT:
    MOVEA.L     (A7)+,A1                        | A1 = return address
    MOVE.W      (A7)+,D2                        | D2 = requested size
    BNE.B       REALFONT_GOT_SIZE               | nonzero -> use it
    TST.W       (A7)                            | family parameter nonzero?
    BNE.B       REALFONT_DEFAULT_SIZE           | yes -> use default size
    MOVE.W      (SysFontSize).W,D2              | try system font size
    BNE.B       REALFONT_GOT_SIZE               | nonzero ->
REALFONT_DEFAULT_SIZE:
    MOVEQ.L     #0x0,D2                         | clear D2
    MOVE.B      (FMDefaultSize).W,D2            | try Font Mgr default size
    BNE.B       REALFONT_GOT_SIZE               | nonzero ->
    MOVEQ.L     #0xC,D2                         | fall back to 12pt
REALFONT_GOT_SIZE:
    MOVE.W      (A7)+,D1                        | D1 = familyID
    CLR.W       (A7)                            | result := false (default)
    MOVE.W      #0xFFFF,(ROMMapInsert).W        | search ROM map first
    BSR.B       FMResolveFamily                 | look up FOND for family
    BEQ.B       REALFONT_TRY_OLDFONT            | not found -> try old FONT
    MOVEA.L     (A0),A0                         | A0 = FOND data ptr
    LEA.L       0x34(A0),A0                     | A0 -> font association table
    MOVE.W      (A0)+,D0                        | D0 = entry count - 1
    BMI.B       REALFONT_RTS                    | empty table -> not real
REALFONT_FOND_LOOP:
    CMP.W       (A0),D2                         | this entry == requested size?
    BEQ.B       REALFONT_FOUND                  | yes -> result := true
    BLT.B       REALFONT_RTS                    | requested < entry -> not present
    ADDQ.W      #0x6,A0                         | next entry (6 bytes)
    DBF.W       D0,REALFONT_FOND_LOOP           | loop
    BRA.B       REALFONT_RTS                    | exhausted -> false
REALFONT_TRY_OLDFONT:
    CMPI.W      #0x200,D1                       | family >= 512?
    BCC.B       REALFONT_RTS                    | yes -> can't be old FONT
    ASL.W       #0x7,D1                         | family << 7 = base FONT ID
    ANDI.W      #0x7F,D2                        | mask size to 7 bits
    OR.W        D2,D1                           | combine to FONT ID
    BSR.W       SWAPFONT_CONT_26                | try loading FONT resource
    BEQ.B       REALFONT_RTS                    | not found ->
REALFONT_FOUND:
    ADDQ.B      #0x1,(A7)                       | result := true
| Called by: REALFONT_FOND_LOOP, REALFONT_TRY_OLDFONT, REALFONT_GOT_SIZE
REALFONT_RTS:
    JMP         (A1)                            | tail-call return from REALFONT_RTS via A1
| ----------------------------------------------------------
| GETFNUM_BODY: GetNamedResource helper - load resource by type/name.
| D0 = resource type, D1 = name string ptr; returns D0 = handle.
GETFNUM_BODY:
    SUBQ.W      #0x4,A7                         | space for handle result
    MOVE.L      D0,-(A7)                        | push resource type
    MOVE.L      D1,-(A7)                        | push name ptr
    MOVE.W      #0xFF00,(ROMMapInsert).W        | include ROM
    _GetNamedResource                           | look up by name
    MOVE.L      (A7)+,D0                        | D0 = handle (or nil)
    RTS                                         | return Z=found
| _GetFNum ($A900): get font number from font name
| Pascal: procedure GetFNum(fontName: Str255; VAR theNum: INTEGER);
GETFNUM:
    MOVE.L      0x8(A7),D1                      | D1 = font name pointer
    MOVE.L      (A7)+,0x4(A7)                   | shift name down (Pascal cleanup)
    MOVEA.L     (A7)+,A1                        | A1 = return address
    MOVE.L      #0x464F4E44,D0                  | D0 = 'FOND'
    BSR.B       GETFNUM_BODY                    | look up FOND by name
    BNE.B       GETFNUM_VIA_FOND                | found ->
    MOVE.L      #0x464F4E54,D0                  | D0 = 'FONT'
    BSR.B       GETFNUM_BODY                    | look up FONT by name
    BNE.B       GETFNUM_VIA_OLDFONT             | found old FONT ->
    CLR.W       (A1)                            | not found: theNum := 0
    BRA.B       GETFNUM_RTS                     | -> return
GETFNUM_VIA_FOND:
    ST.B        D1                              | D1 = true (found via FOND)
    BRA.B       GETFNUM_GET_INFO                | -> get resource info
GETFNUM_VIA_OLDFONT:
    SF.B        D1                              | D1 = false (old-style FONT)
GETFNUM_GET_INFO:
    MOVE.L      D0,-(A7)                        | push resource handle
    MOVE.L      A1,-(A7)                        | push caller's VAR theNum
    CLR.L       -(A7)                           | placeholder for resType
    CLR.L       -(A7)                           | placeholder for resID
    MOVE.W      #0xFF00,(ROMMapInsert).W        | include ROM
    _GetResInfo                                 | get resource info
    TST.B       D1                              | found via FOND?
    BNE.B       GETFNUM_RTS                     | yes -> ID is family directly
    MOVE.W      (A1),D0                         | D0 = resource ID (FONT)
    LSR.W       #0x7,D0                         | extract family bits (>> 7)
    MOVE.W      D0,(A1)                         | store family in caller's VAR
GETFNUM_RTS:
    RTS                                         | return from GETFNUM_RTS
| _SetFontLock ($A903): lock/unlock current font in memory
| Pascal: procedure SetFontLock(lockFlag: BOOLEAN);
SETFONTLOCK:
    MOVEA.L     (FOutFontHandle).W,A0           | A0 = current font handle
    MOVEA.L     (A7)+,A1                        | A1 = return address
    TST.B       (A7)+                           | lock or unlock?
    BEQ.B       SETFONTLOCK_PURGE               | unlock ->
    MOVE.L      A0,-(A7)                        | push handle for LoadResource
    MOVE.W      #0xFFFF,(ROMMapInsert).W        | search ROM map first
    _LoadResource                               | ensure font is in memory
    _HNoPurge                                   | mark non-purgeable
    BCLR        #0x6,(FondState)                | clear FOND saved-purge bit
    BRA.B       SETFONTLOCK_RTS                 | -> return
SETFONTLOCK_PURGE:
    _HPurge                                     | mark purgeable (unlocked)
    BSET        #0x6,(FondState)                | set FOND saved-purge bit
SETFONTLOCK_RTS:
    JMP         (A1)                            | tail-call return from SETFONTLOCK_RTS via A1
| _SetFScaleDisable ($A834): set scale-disable flag
| Pascal: procedure SetFScaleDisable(fscaleDisable: BOOLEAN);
SETFSCALEDISABLE:
    MOVEA.L     (A7)+,A0                        | A0 = return address
    MOVE.B      (A7)+,(FScaleDisable).W         | store boolean param
SETFSCALE_INVALIDATE:
    MOVE.L      (MinusOne).W,(LastSPExtra).W    | invalidate LastSPExtra cache
    JMP         (A0)                            | tail-call return from SETFSCALE_INVALIDATE via A0
| _SetFractEnable ($A814): set fractional-widths flag
| Pascal: procedure SetFractEnable(fractEnable: BOOLEAN);
SETFRACTENABLE:
    MOVEA.L     (A7)+,A0                        | A0 = return address
    MOVE.B      (A7)+,(FractEnable).W           | store boolean param
    BRA.B       SETFSCALE_INVALIDATE            | -> invalidate cache + return
| _FontMetrics ($A835): return detailed font metrics for current font
| Pascal: procedure FontMetrics(VAR theMetrics: FMetricRec);
FONTMETRICS:
    SUBQ.W      #0x2,A7                         | space for CharWidth result
    MOVE.W      #0x20,-(A7)                     | push space character
    _CharWidth                                  | force font swap if needed
    ADDQ.W      #0x2,A7                         | discard width
    MOVE.L      A2,-(A7)                        | save A2
    MOVEA.L     0x8(A7),A2                      | A2 = output FMetricRec ptr
    MOVEA.L     (FOutFontHandle).W,A1           | current font handle
    MOVEA.L     (A1),A1                         | dereference
    LEA.L       0x12(A1),A0                     | A0 -> font strike metrics area
    PEA.L       0x6(A1)                         | push font bounds rect ptr
    BSR.B       ScaleVFVal                      | scale and store metric 1 (ascent)
    BSR.B       ScaleVFVal                      | scale and store metric 2 (descent)
    BSR.B       ScaleVFVal                      | scale and store metric 3 (leading)
    MOVEA.L     (A7)+,A0                        | A0 = font bounds rect
    MOVE.L      (FScaleHFact).W,D1              | horizontal scale factor
    LEA.L       (FOutNumer_v).W,A1              | A1 -> scaling numer/denom (vert)
    BSR.B       ScaleFVal                       | scale widMax
    MOVEA.L     (WidthTabHandle).W,A0           | A0 = width table handle
    MOVE.L      A0,(A2)                         | store widthTabHandle in output
    MOVEA.L     0x8(A7),A2                      | A2 = output FMetricRec ptr
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.B      (FOutShadow).W,D0               | shadow offset?
    BEQ.B       FONTMETRICS_NO_SHADOW           | none ->
    ADDQ.W      #0x1,(A2)                       | ascent += 1 (shadow extends up)
    ADD.W       D0,0x4(A2)                      | widMax += shadow offset
FONTMETRICS_NO_SHADOW:
    MOVEA.L     (A0),A0                         | A0 = widthTab data
    MOVE.L      0x408(A0),D0                    | D0 = spExtra from width table
    ADD.L       D0,0xC(A2)                      | add spExtra to leading in output
    MOVEA.L     (A7)+,A2                        | restore A2
    MOVE.L      (A7)+,(A7)                      | strip param (shift ret addr down)
    RTS                                         | return from FontMetrics
| ----------------------------------------------------------
|
| ScaleVFVal
|
| ScaleVFVal: scale metric by vertical factor with numer/denom
ScaleVFVal:
    MOVE.L      (FScaleVFact).W,D1              | D1 = vertical scale factor
    LEA.L       (FOutNumer_h).W,A1              | A1 = numer/denom for vertical
ScaleFVal:
    MOVE.W      (A0)+,D0                        | D0 = next metric word
    MOVE.L      A0,-(A7)                        | save metrics pointer
    TST.B       (FScaleDisable).W               | scaling enabled?
    BNE.B       FONTMETRICS_OK                  | no -> use D1 as-is
    MOVE.L      FPOINTONE(PC),D1                | D1 = 1.0 (no scaling)
FONTMETRICS_OK:
    SUBQ.W      #0x4,A7                         | space for 1st FixMul result
    MOVE.L      D1,-(A7)                        | push scale factor
    SUBQ.W      #0x4,A7                         | space for 2nd FixMul result
    CLR.W       -(A7)                           | high word = 0
    MOVE.W      D0,-(A7)                        | push metric (16.16 fixed)
    SUBQ.W      #0x4,A7                         | space for FixRatio result
    MOVE.W      (A1),-(A7)                      | push numer.h
    MOVE.W      0x4(A1),-(A7)                   | push denom.h
    _FixRatio                                   | numer/denom
    _FixMul                                     | metric * ratio
    _FixMul                                     | result * scale
    MOVE.L      (A7)+,(A2)+                     | store scaled metric in output
    MOVEA.L     (A7)+,A0                        | restore metrics pointer
    RTS                                         | return next metric stored
| BUILDBBOX_BODY (= INVERTCOLOR_CONT_3 in Plus): build per-glyph
| bounding box table appended to the font strike. Scans the strike's
| bitmap to find the top/bottom ink row of each glyph. Used by
| QuickDraw for faster text clipping.
| A0 = font handle; modifies the strike via _SetHandleSize.
BUILDBBOX_BODY:
    MOVEM.L     D3-D7/A2-A5,-(A7)               | save callee-saved regs
    MOVEA.L     A0,A3                           | A3 = font handle
    _GetMaskTable                               | A0 = MaskBC table (16-bit masks)
    MOVEA.L     A0,A5                           | A5 = mask table base
    MOVEA.L     (A3),A1                         | A1 = font strike data
    MOVE.W      (A1)+,D0                        | D0 = fontType
    LSR.W       #0x1,D0                         | bit 0 = bbox table present?
    BCS.B       BUILDBBOX_ALREADY_DONE          | already built -> return
    MOVE.W      (A1)+,D0                        | D0 = firstChar
    MOVEQ.L     #0x0,D5                         | clear D5
    MOVE.W      (A1),D5                         | D5 = lastChar
    SUB.W       D0,D5                           | D5 = char range
    ADDQ.W      #0x3,D5                         | + missing + 2 entries
    ADD.W       D5,D5                           | * 2 bytes per bbox entry
    MOVEA.L     (A3),A1                         | re-dereference (may have moved)
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.W      0x10(A1),D0                     | D0 = rowWords
    ADDQ.L      #0x8,D0                         | + 8 header words
    ADD.L       D0,D0                           | * 2 = byte offset to bitmap end
    MOVE.L      D0,D1                           | D1 = offset to width table area
    SUB.L       D5,D1                           | adjust for table layout
    ADD.L       D5,D0                           | D0 = past offset/width table
    MOVE.L      D0,D2                           | D2 = offset to bbox table
    ADD.L       D5,D0                           | D0 = new total size with bbox
    BTST        #0x1,0x1(A1)                    | font has 16-bit widths?
    BEQ.B       BUILDBBOX_RESIZE                | no ->
    ADD.L       D5,D0                           | add space for extra width table
    ADD.L       D5,D2                           | adjust bbox table offset
BUILDBBOX_RESIZE:
    MOVEA.L     A3,A0                           | A0 = font handle
    _SetHandleSize                              | resize to add bbox area
    BEQ.B       BUILDCHARTABLE_CONT_4           | success -> build bbox table
BUILDBBOX_ALREADY_DONE:
    MOVEM.L     (A7)+,D3-D7/A2-A5               | restore regs
    RTS                                         | return (already done or failed)
| ----------------------------------------------------------
|
| BUILDCHARTABLE_CONT_4
|
| BUILDCHARTABLE_CONT_4: resize succeeded - build bbox table by scanning bitmap
| Called during boot.
BUILDCHARTABLE_CONT_4:
    MOVEA.L     (A3),A2                         | A2 = font strike data
    ORI.W       #0x1,(A2)                       | set fontType bit 0 (bbox present)
    MOVE.W      0xE(A2),D3                      | D3 = fRectHeight (bitmap rows)
    ADDA.L      D1,A2                           | A2 -> offset/width table
    MOVEA.L     (A3),A4                         | A4 = font data base
    ADDA.L      D2,A4                           | A4 -> bbox output table
    SUBQ.W      #0x2,D5                         | D5 = loop counter (entries - 1)
BUILDCHARTABLE_NEXT:
    MOVE.W      #0xFF00,(A4)                    | init bbox entry ($FF00 = no ink)
    MOVE.W      (A2)+,D7                        | D7 = glyph X start (bit offset)
    MOVE.W      (A2),D6                         | D6 = next glyph X start
    SUB.W       D7,D6                           | D6 = glyph pixel width
    BEQ.B       BUILDCHARTABLE_EMPTY            | zero width (space) ->
| BUILDCHARTABLE_NEXT_2: build bit mask for glyph columns, scan bitmap rows
BUILDCHARTABLE_NEXT_2:
    MOVE.W      D7,D2                           | D2 = bit position
    MOVE.W      D7,D0                           | D0 = bit position
    LSR.W       #0x4,D0                         | D0 = word index in row
    ADD.W       D0,D0                           | * 2 = byte offset
    MOVEA.L     (A3),A1                         | re-dereference handle
    ADDA.W      #0x1A,A1                        | A1 -> bitmap data start
    ADDA.W      D0,A1                           | A1 = column word in bitmap
    ANDI.W      #0xF,D2                         | D2 = bit position within word
    MOVE.W      D2,D1                           | D1 = bit position
    ADD.W       D1,D1                           | * 2 for word table index
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.W      0x20(A5,D1.W),D0                | D0 = right-aligned bitmask
    SWAP.W      D0                              | move to high word (long mask)
    MOVEQ.L     #0x10,D4                        | D4 = 16 bits per word
    MOVE.W      D4,D1                           | D1 = bits per word
    SUB.W       D2,D1                           | D1 = remaining bits in word
    ADD.W       D1,D7                           | advance X past this word
    SUB.W       D1,D6                           | D6 = remaining glyph width
    BEQ.B       BUILDCHARTABLE_CONT_7           | fits in one word ->
    BPL.B       BUILDBBOX_WIDE_GLYPH            | spans multiple words ->
    MOVE.W      D6,D1                           | D1 = negative overshoot
    ADD.W       D4,D1                           | adjust to positive
    ADD.W       D1,D1                           | * 2 for table index
    MOVE.L      0x0(A5,D1.W),D2                 | D2 = right-side mask
    AND.L       D2,D0                           | narrow column mask
    BRA.B       BUILDCHARTABLE_CONT_7           | -> scan with mask
BUILDBBOX_WIDE_GLYPH:
    MOVE.W      D6,D1                           | D1 = remaining glyph width
    CMP.W       D4,D1                           | more than 16 left?
    BLE.B       BUILDCHARTABLE_NO_3             | no ->
    MOVE.W      D4,D1                           | clamp to 16
BUILDCHARTABLE_NO_3:
    ADD.W       D1,D1                           | * 2 for table index
    MOVE.W      0x0(A5,D1.W),D2                 | D2 = mask for right-side bits
    OR.W        D2,D0                           | extend column mask rightward
    SUB.W       D4,D6                           | reduce remaining width
    ADD.W       D4,D7                           | advance X position
BUILDCHARTABLE_CONT_7:
    MOVE.L      A1,-(A7)                        | save bitmap column pointer
    MOVE.W      D3,D1                           | D1 = fRectHeight (row count)
    SUBQ.W      #0x1,D1                         | adjust for DBF
    MOVEA.L     (A3),A0                         | re-deref font handle
    MOVEA.W     0x18(A0),A0                     | A0 = rowWords
    ADDA.W      A0,A0                           | A0 = rowBytes
    MOVEQ.L     #0x0,D4                         | D4 = current row (top -> down)
BUILDCHARTABLE_LOOP:
    MOVE.L      (A1),D2                         | D2 = bitmap data at this row
    AND.L       D0,D2                           | mask to glyph columns
    BNE.B       BUILDCHARTABLE_FOUND            | ink found -> record top row
    ADDQ.W      #0x1,D4                         | next row
    ADDA.W      A0,A1                           | advance to next bitmap row
    DBF.W       D1,BUILDCHARTABLE_LOOP          | loop all rows
    ADDQ.L      #0x4,A7                         | discard saved pointer (no ink)
    MOVEQ.L     #0x0,D6                         | D6 = 0 (no more columns)
BUILDCHARTABLE_EMPTY:
    CLR.W       (A4)+                           | store 0 in bbox (empty glyph)
    BRA.B       BUILDCHARTABLE_NEXT_3           | -> next glyph
BUILDCHARTABLE_FOUND:
    CMP.B       (A4),D4                         | top row < current min?
    BCC.B       BUILDCHARTABLE_NO_4             | no ->
    MOVE.B      D4,(A4)                         | update top row (min ascent)
| BUILDCHARTABLE_NO_4: scan bitmap rows from bottom up for last ink row
BUILDCHARTABLE_NO_4:
    MOVEA.L     (A7)+,A1                        | restore bitmap column pointer
    MOVE.W      D3,D2                           | D2 = fRectHeight
    SUBQ.W      #0x1,D2                         | D2 = last row index
    MOVE.W      A0,D4                           | D4 = rowBytes
    MULU.W      D4,D2                           | D2 = byte offset to last row
    ADDA.L      D2,A1                           | A1 = last row of this column
    MOVE.W      D3,D4                           | D4 = fRectHeight (bottom row + 1)
    MOVE.W      D3,D1                           | D1 = loop counter
    SUBQ.W      #0x1,D1                         | adjust for DBF
BUILDCHARTABLE_LOOP_2:
    MOVE.L      (A1),D2                         | D2 = bitmap data at this row
    AND.L       D0,D2                           | mask to glyph columns
    BNE.B       BUILDBBOX_BOTTOM_FOUND          | ink found -> record bottom row
    SUBQ.W      #0x1,D4                         | move up one row
    SUBA.W      A0,A1                           | back up one row
    DBF.W       D1,BUILDCHARTABLE_LOOP_2        | loop all rows
    BRA.B       BUILDCHARTABLE_EMPTY            | no ink at all -> empty entry
BUILDBBOX_BOTTOM_FOUND:
    ADDQ.L      #0x1,A4                         | step to bbox bottom byte
    CMP.B       (A4)+,D4                        | bottom row > current max?
    BCS.B       BUILDCHARTABLE_NEXT_3           | no ->
    MOVE.B      D4,-0x1(A4)                     | update bottom row (max descent)
BUILDCHARTABLE_NEXT_3:
    SUBQ.L      #0x2,A4                         | rewind A4 to bbox entry start
    TST.W       D6                              | more columns to scan?
    BGT.W       BUILDCHARTABLE_NEXT_2           | yes -> next column block
    MOVE.B      (A4)+,D0                        | D0 = top row
    SUB.B       D0,(A4)+                        | bbox.height = bottom - top
    SUBQ.W      #0x2,D5                         | next glyph
    BGT.W       BUILDCHARTABLE_NEXT             | more glyphs ->
    BRA.W       BUILDBBOX_ALREADY_DONE          | -> restore regs + return
