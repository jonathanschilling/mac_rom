| Sad Mac / Happy Mac icon display (ROM $078E-$09F9).
| Called after a boot-time memtest or self-test failure to render the
| sad-face (or happy-face) glyph on the boot screen.
|
| Entry points:
| ShowSadMac @ $07CC -- A5 = return addr, draws the Mac-outline
| icon + sad-face overlay.
| ShowHappyMac @ $07F4 -- ShowHappyMac alt-entry (smile glyph).
|
| Internal helpers:
| DeviceLoop @ $078E -- DeviceLoop icon-row
| decoder for the RLE-compressed Mac-outline icon.
| ICON_XOR_PROPAGATE @ $07BC -- after RLE decode, delta-XOR each row
| with the one above to reconstruct the bitmap.
| PutSymbol @ $07FA -- copy a small glyph bitmap into the
| current screen cell.
|
| Data blocks in this range:
| DT_mSadMac @ $08B4 -- sad-face glyph bitmap (16 rows).
| ICON_MAC_OUTLINE @ $080C -- RLE-compressed Mac-shaped outline.
|
| DS-alert support (LOOKUP_LOOP / LOOKUP_FOUND @ $09DC) used by the
| system error handler in sys_error.s to find an alert string by ID.

DeviceLoop:                                     | DeviceLoop entry
        ADDA.L  A3,A2                           | A2 += RAM base (screen buffer)
        MOVEQ.L #0xF,D3                         | D3 = 15 (16 rows to decode)
        MOVE.L  A2,A0                           | A0 = save screen start for XOR-propagate
        MOVEQ.L #0x3,D2                         | D2 = 3 (4 bytes per row before row-skip)
| ----------------------------------------------------------
| DeviceLoop inner row -- decode one 32-pixel row from RLE icon data
ICON_ROW_LOOP:                                  | ICON_ROW_LOOP
        MOVE    #0x100,D4                       | D4 bit 8 = sentinel (detect end of flag byte)
        MOVE.B  (A4)+,D4                        | D4 low byte = run-length flag bits
ICON_BIT_LOOP:                                  | ICON_BIT_LOOP
        LSR     #0x1,D4                         | shift next flag bit into carry
        BEQ.B   ICON_NEXT_ROW                   | sentinel reached: 8 bits consumed, next row
        BCC.B   ICON_COPY_BYTE                  | carry=0: data byte comes from (A4) (skip zero)
        CLR.B   (A2)+                           | carry=1: write zero (white pixel column)
        BRA.B   ICON_BYTE_COUNT                 | -> byte counter
ICON_COPY_BYTE:                                 | ICON_COPY_BYTE
        MOVE.B   (A4)+,(A2)+                    | copy icon-data byte to screen buffer
ICON_BYTE_COUNT:                                | ICON_BYTE_COUNT
        DBRA    D2,ICON_BIT_LOOP                | continue decoding current flag byte
        ADDA.W  #0x3C,A2                        | skip remaining bytes to next screen row (60)
        MOVEQ.L #0x3,D2                         | reset byte counter (4 bytes per group)
        BRA.B   ICON_BIT_LOOP                   | continue decoding
ICON_NEXT_ROW:                                  | ICON_NEXT_ROW
        DBRA    D3,ICON_ROW_LOOP                | 16 rows total
        MOVE.L  A0,A1                           | A1 = icon start row (source for XOR)
        MOVEQ.L #0x1E,D3                        | D3 = 30: propagate icon down 31 more rows
| XOR each row with the previous to reconstruct delta-encoded image
ICON_XOR_PROPAGATE:
        ADDA.W  #0x40,A1                        | advance A1 to next screen row (64 bytes/row)
        MOVE.L  (A0),D4                         | D4 = previous row's 4 bytes (32 pixels)
        EOR.L   D4,(A1)                         | XOR previous row into current (delta decode)
        MOVE.L  A1,A0                           | current row becomes source for next iteration
        DBRA    D3,ICON_XOR_PROPAGATE           | repeat for 31 rows
        JMP     (A6)                            | jump via A6
| ----------------------------------------------------------
| ShowSadMac -- draw sad-Mac icon on boot screen after test failure
| Return address in A5. Encodes as `LEA 0xE6(PC),A0` which loads A0
| with the pointer to the sad-face glyph data at $08B4 (DT_mSadMac),
| then falls through into DRAW_MAC_ICON's common outline+overlay loop.
ShowSadMac:
        LEA     DT_mSadMac(PC),A0               | A0 = sad-face glyph data at $08B4
DRAW_MAC_ICON:                                  | DRAW_MAC_ICON
        LEA     ICON_MAC_OUTLINE(PC),A4         | A4 = compressed Mac outline icon
        MOVE.L  A0,D7                           | D7 = save face-data ptr across DeviceLoop
        MOVE.L  #0x7CB5E,A2                     | A2 = SEScrnIcon (centered screen pos)
        LEA     DRAW_FACE_OVERLAY(PC),A6        | return to DRAW_FACE_OVERLAY after outline
        BRA.B   DeviceLoop                      | decode and draw Mac outline icon
DRAW_FACE_OVERLAY:                              | DRAW_FACE_OVERLAY
        MOVE.L  #0x7CCDF,A2                     | A2 = SEScrnFace (face position in icon)
        MOVE.L  D7,A4                           | A4 = face data (sad/happy, saved in D7)
        LEA     ICON_DRAW_RETURN(PC),A6         | return to ICON_DRAW_RETURN after face
        BRA.W   PutSymbol                       | draw 10-row face bitmap (PutSymbol)
ICON_DRAW_RETURN:                               | ICON_DRAW_RETURN
        JMP     (A5)                            | return to original caller
ShowHappyMac:                                   | ShowHappyMac entry
        LEA     DT_mHappyMac(PC),A0             | A0 = happy-face glyph data
        BRA.B   DRAW_MAC_ICON                   | draw outline + happy face
PutSymbol:                                      | PutSymbol prologue
        ADDA.L  A3,A2                           | A2 += RAM base (adjust to real screen addr)
        MOVEQ.L #0x9,D2                         | D2 = 9 (10 rows to draw)
PUTSYMBOL_LOOP:                                 | copy one bitmap row
        MOVE.B  (A4)+,(A2)+                     | copy left byte of row
        MOVE.B  (A4)+,(A2)+                     | copy right byte of row
        ADDA.W  #0x3E,A2                        | skip to next screen row (64 - 2 written)
        DBRA    D2,PUTSYMBOL_LOOP               | repeat for all 10 rows
PUTSYMBOL_EXIT:
        JMP     (A6)                            | return to caller

| ==========================================================================
| $080C..$0903 -- boot-screen icon + face glyph data tables.
| Six bitmap tables used by DeviceLoop (RLE decoder, above) and
| PUTSYMBOL_LOOP to draw the boot screen:
| ICON_MAC_OUTLINE @ $080C (100 B) Mac computer outline, RLE-encoded
| ICON_DISK @ $0870 ( 48 B) floppy-disk icon (retry animation)
| DT_mHappyMac @ $08A0 ( 20 B) happy-face glyph (10 rows x 2 B)
| DT_mSadMac @ $08B4 ( 20 B) sad-face glyph (10 rows x 2 B)
| DT_mQMark @ $08C8 ( 30 B) question-mark glyph (15 rows x 2 B)
| DT_mXMark @ $08E6 ( 30 B) X-mark glyph (15 rows x 2 B)
| FDisasm originally rendered this region as a chaotic mix of "fake"
| instructions because several byte values happen to encode legal
| 68000 mnemonics. Rewritten here as pure `.byte` data with per-row
| commentary. Byte layout matches Plus's src/plus/boot/memtest.s
| tables exactly (lines 349-402).
| ==========================================================================

| ICON_MAC_OUTLINE -- compressed Macintosh computer outline (32-pixel wide,
| delta-encoded). Consumed row-by-row by DeviceLoop (which writes into
| SEScrnIcon). 100 bytes: 16 rows x 6 bytes + 4-byte base bottom.
ICON_MAC_OUTLINE:
        .byte   0x00,0x57,0xFF,0xFF,0xD5,0xFF   | rows 1-2 (top edge)
        .byte   0xFF,0xFF,0xFF,0x06,0xF8,0x3F   | rows 2-3 (bezel top corners)
        .byte   0xE1,0xFF,0xFF,0x0F,0x60,0xE3   | rows 3-4 (screen area top)
        .byte   0xFF,0xFF,0x8F,0xE0,0x0F,0x66   | rows 4-5 (screen L/R borders)
        .byte   0xE0,0x0F,0xE0,0x0F,0x66,0xE0   | rows 5-6 (screen interior)
        .byte   0x0F,0xE0,0x0F,0x66,0xE0,0x0F   | rows 6-7 (screen interior)
        .byte   0xE0,0x0F,0x66,0xE0,0x0F,0xE0   | rows 7-8 (screen interior)
        .byte   0x0F,0x66,0xE0,0x0F,0xE0,0x0F   | rows 8-9 (screen interior)
        .byte   0x06,0xE0,0x0F,0xE3,0xFF,0xFF   | rows 9-10 (screen bottom)
        .byte   0x8F,0x60,0xE1,0xFF,0xFF,0x0F   | rows 10-11 (bezel divider)
        .byte   0xE0,0x0F,0x66,0xE0,0x0F,0xE0   | rows 11-12 (floppy slot area)
        .byte   0x0F,0x22,0xE3,0x3F,0x0F,0xE3   | rows 12-13 (floppy slot detail)
        .byte   0x3F,0x0F,0x66,0xE0,0x0F,0xE0   | rows 13-14 (lower bezel)
        .byte   0x0F,0x06,0xE0,0x0F,0xFF,0xFF   | rows 14-15 (bezel bottom)
        .byte   0xFF,0xFF,0x60,0xF7,0xFF,0xFF   | rows 15-16 (base top)
        .byte   0xDF,0xF0,0x1F,0x06,0xF0,0x1F   | rows 16+ (base front)
        .byte   0xF7,0xFF,0xFF,0xDF             | base bottom edge

| ----------------------------------------------------------
| ICON_DISK -- 32x16 floppy-disk icon used during the read-failure
| animation that cycles between Mac outline and disk. 48 bytes:
| 8 rows x 6 bytes. Also decoded by DeviceLoop.
ICON_DISK:
        .byte   0x00,0x7F,0xFF,0xFF,0xF5,0xFE   | rows 1-2 (top edge)
        .byte   0xFF,0xFE,0xFF,0x33,0x70,0x0F   | rows 2-3 (disk label area)
        .byte   0xF8,0x07,0xF7,0x03,0xFF,0xBB   | rows 3-4 (label detail)
        .byte   0xF8,0x70,0x98,0x01,0xFF,0xFF   | rows 4-5 (metal slider area)
        .byte   0xFF,0xFE,0xFF,0x00,0x07,0xFF   | rows 5-6 (disk body)
        .byte   0xFF,0xE0,0x0F,0xFF,0xFF,0xF0   | rows 6-7 (disk body centre)
        .byte   0xFF,0xFF,0xFF,0xFF,0xFF,0xFF   | rows 7-8 (disk body lower)
        .byte   0xFF,0x0F,0x77,0xFF,0xFF,0xEF   | rows 8+ (disk bottom edge)

| ----------------------------------------------------------
| DT_mHappyMac -- happy-face overlay (10 rows x 2 bytes = 20 bytes).
| Drawn on top of ICON_MAC_OUTLINE's screen area to show "boot success".
DT_mHappyMac:
        .byte   0x00,0x00,0x11,0x10,0x11,0x10   | rows 1-3 (blank, eyes, eyes)
        .byte   0x01,0x00,0x01,0x00,0x03,0x00   | rows 4-6 (nose, nose, nose bridge)
        .byte   0x00,0x00,0x08,0x40,0x07,0x80   | rows 7-9 (blank, smile corners)
        .byte   0x00,0x00                       | row 10 (smile arc tail)

| ----------------------------------------------------------
| DT_mSadMac -- sad-face overlay (10 rows x 2 bytes = 20 bytes). Drawn
| when the boot read fails repeatedly. Eyes are X-shapes; frown at bottom.
DT_mSadMac:
        .byte   0x28,0x28,0x10,0x10,0x28,0x28   | rows 1-3 (X eyes L/centre/R)
        .byte   0x00,0x00,0x04,0x80,0x03,0x00   | rows 4-6 (blank, nose, bridge)
        .byte   0x00,0x00,0x0F,0xC0,0x10,0x30   | rows 7-9 (blank, frown top)
        .byte   0x00,0x08                       | row 10 (frown arc)

| ----------------------------------------------------------
| DT_mQMark -- question-mark glyph (15 rows x 2 bytes = 30 bytes).
| Overlay for "?" icon shown during initial disk-search animation.
DT_mQMark:
        .byte   0x00,0x00,0x00,0x00,0x07,0xE0   | rows 1-3 (blank, blank, top arc)
        .byte   0x0F,0xF0,0x0C,0x30,0x0C,0x30   | rows 4-6 (full arc, right side)
        .byte   0x00,0x70,0x00,0xE0,0x01,0xC0   | rows 7-9 (curve, curve, stem)
        .byte   0x01,0x80,0x01,0x80,0x00,0x00   | rows 10-12 (stem, stem, blank)
        .byte   0x01,0x80,0x01,0x80,0x00,0x00   | rows 13-15 (dot, dot, blank)

| ----------------------------------------------------------
| DT_mXMark -- X-mark glyph (15 rows x 2 bytes = 30 bytes). Overlay
| shown when the read fails on a specific drive.
DT_mXMark:
        .byte   0x00,0x00,0x00,0x00,0x10,0x08   | rows 1-3 (blank, blank, outer tips)
        .byte   0x38,0x1C,0x1C,0x38,0x0E,0x70   | rows 4-6 (upper arms, crossing, narrow)
        .byte   0x07,0xE0,0x03,0xC0,0x03,0xC0   | rows 7-9 (centre top, centre, centre bot)
        .byte   0x07,0xE0,0x0E,0x70,0x1C,0x38   | rows 10-12 (widen, lower arms, spread)
        .byte   0x38,0x1C,0x10,0x08,0x00,0x00   | rows 13-15 (outer tips, endpoints, blank)

| ----------------------------------------------------------
| INSTALL_DSERR_TRAMP -- install the sad-Mac trampoline at two
| low-memory vector slots. Called from SysErrInit during boot.
| A6 = work-area base (set up earlier)
| Writes SysErrTrampoline's address ($091E) at two consecutive
| long-word slots so that system-error vectors point at the trampoline.
INSTALL_DSERR_TRAMP:
        LEA     0x18(A6),A1                     | A1 = first stash slot
        LEA     0x6C(A6),A0                     | A0 = second stash slot
        MOVE.L  A0,(A1)+                        | stash1 := A0
        ADDQ.W  #0x4,A0                         | advance A0 to stash2+4 (second vector slot)
        MOVE.L  A0,(A1)+                        | stash1+4 := A0
        LEA     SysErrTrampoline(PC),A1         | A1 = trampoline handler @ $091E
        MOVE.L  A1,(A0)                         | install trampoline at stash2
        SUBQ.W  #0x4,A0                         | A0 back to stash2 (first slot of pair)
        MOVE.L  A1,(A0)                         | also install at stash2-4
        RTS                                     | return to system error init

| ----------------------------------------------------------
| SysErrTrampoline -- sad-Mac alert trampoline.
| Entered via the vectors installed by INSTALL_DSERR_TRAMP. The lead
| `.short 0x000A` is a signature/header word; real execution starts
| after the two `.short 0x8AD0` alignment words, at the MOVEQ.
SysErrTrampoline:
        .short  0x000A                          | trampoline signature word
        .short  0x8AD0                          | alignment pad (decodes as DIVU.W)
        .short  0x8AD0                          | alignment pad (decodes as DIVU.W)
| Real handler body starts here. The bytes 7530 7530 48E7 FF7E looked
| like one long "mvsb" to FDisasm, but are really two MOVEQ instructions
| followed by MOVEM.L register save.
        .short  0x7530, 0x7530                  | MOVEQ #0x30,D2 (pair)
        .short  0x48E7, 0xFF7E                  | MOVEM.L D0-D7/A1-A6,-(SP)
        MOVE    0x3C(SP),D3                     | D3 = saved exception code from frame
        SUBA.L  A3,A3                           | A3 = 0 (RAM-base offset for screen addr)
        LEA.L     SYSBEEP_EPILOG(PC),A6         | A6 = epilogue (pop regs + RTS)
        BRA.W   BootBeep                        | beep then draw sad Mac

| ----------------------------------------------------------
| SYSBEEP_EPILOG - SysBeep epilogue, pops duration param and returns
SYSBEEP_EPILOG:
        MOVEM.L (SP)+,D0-D7/A1-A6               | restore caller-saved regs
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x2,SP                         | discard duration parameter word
        JMP     (A0)                            | return to SysBeep caller
| ----------------------------------------------------------
| SysError -- fatal-error system-reset entry point
| Reached when an unrecoverable error has been signalled (D0 = err
| code). Saves ALL registers and PC to SERegs ($7FC80), clears the
| framebuffer, opens a grafport on the screen, then draws the sad-Mac
| alert dialog. Also the target of `BRA.W SysError` in
| PLOTDISK_AFTER_ICON_CONT (vectors.s $0594).
SysError:                                       | SysError entry (fatal)
        MOVEM.L D0-D7/A0-A7,(0x0007FC80).l      | save all registers to SERegs ($7FC80)
SysErr2:
        MOVE.L  (SP),(0x0007FCC0).l             | save PC (ret addr from caller) to SERegs+0x40
        MOVEM.L D0-A6,-(SP)                     | save current working registers
        MOVE    D0,(DSErrCode).w                | DSErrCode = system error code
        TST.L   (DSAlertTab).w                  | custom DS alert table installed?
        BEQ.B   DSERR_SKIP_PROC_CONT            | no: fall to CritErr (blinking screen)
        LEA.L     -4(SP),A5                     | A5 = frame anchor
        SUBA.W  #0x15A,SP                       | reserve 346 bytes for GrafPort + strings
        MOVE.L  SP,A6                           | A6 = work-area base
        MOVE    D0,-(SP)                        | save DS err code on stack
        PEA.L     -4(A5)                        | push &thePort
        _InitGraf                               | InitGraf(&thePort)
        BSR.B   INSTALL_DSERR_TRAMP             | install DSAlertTab trampoline
        MOVE.L  A6,-(SP)                        | push work-area base (the new GrafPort)
        _InitPort                               | InitPort(port)
        TST     (SP)                            | test low word of D0-pushed-earlier
        BMI.B   SysErrAfterFrame                | negative: skip dialog frame
        BSR.W   DRAW_ALERT_FRAME                | draw dialog frame (rect + border)
SysErrAfterFrame:
        MOVE    (SP)+,D0                        | pop saved error code
        BSR.B   LOOKUP_ALERT_ID                 | look up err in alert table
        BNE.B   DSERR_DRAW_ALERT                | found: use the alert definition
        MOVE.L  (DSAlertTab).w,A0               | not found: use default alert (entry 0)
        ADDQ.W  #0x6,A0                         | skip alert-table header (6 bytes)
DSERR_DRAW_ALERT:                               | draw alert using A0's fields
        MOVE.L  A0,A3                           | A3 = ptr to alert definition fields
        BSR.B   DRAW_ALERT_TEXT                 | draw first text field
        BSR.B   DRAW_ALERT_TEXT                 | draw second text field
        MOVE    (A3)+,D0                        | D0 = icon resource ID
        BEQ.B   DSERR_SKIP_ICON                 | 0 = no icon, skip
        BSR.B   LOOKUP_ALERT_ID                 | look up icon ID in table
        BEQ.B   DSERR_SKIP_ICON                 | not found - skip icon draw
        PEA.L     8(A0)                         | push icon rect ptr (past 8-byte header)
        MOVE.L  A0,-(SP)                        | push icon data ptr
        PEA.L     4(SP)                         | push dest rect on stack (reuse rect)
        _PlotIcon                               | draw the alert icon
        ADDQ.W  #0x4,SP                         | pop extra rect ptr
DSERR_SKIP_ICON:
        MOVE    (A3)+,D0                        | D0 = custom procedure resource ID
        BEQ.B   DSERR_SKIP_PROC                 | 0 = no custom procedure
        BSR.B   LOOKUP_ALERT_ID                 | look up procedure in table
        BEQ.B   DSERR_SKIP_PROC                 | not found - skip custom call
        JSR     (A0)                            | run custom alert procedure
DSERR_SKIP_PROC:
        MOVE    (A3)+,D0                        | D0 = button definition ID
        BEQ.B   DSERR_SKIP_PROC_NO              | 0 = no buttons (auto-resume)
        TST.L   (ResumeProc).w                  | resume procedure installed?
        BEQ.B   DSERR_SKIP_PROC_OK              | no: use button count as-is
        ADDQ.W  #0x1,D0                         | yes: add Resume button option
DSERR_SKIP_PROC_OK:
        BSR.W   SHOW_ALERT_BTNS                 | draw buttons and wait for click
        BNE.B   DSERR_SKIP_PROC_NO_2            | got a button click: exit via ResumeProc
DSERR_SKIP_PROC_NO:
        ADDA.W  #0x15A,SP                       | free GrafPort work area
        MOVEM.L (SP)+,D0-A6                     | restore regs
        RTS                                     | return to caller (auto-resume)
DSERR_SKIP_PROC_NO_2:
        JMP     (A0)                            | tail-call ResumeProc
DSERR_SKIP_PROC_CONT:                           | no DSAlertTab: CritErr fallback
        MOVE    D0,D1                           | D1 = err code (for CritErr display)
        MOVE    #0xF,A4                         | A4 = 15 (critical-err glyph row count)
        SUBA.L  A3,A3                           | A3 = nil (no alert text, RAM-base = 0)
        BRA.W   CritErr                         | -> sad-Mac blinking-screen handler
| Called by: SysErrAfterFrame, DSERR_DRAW_ALERT, DSERR_SKIP_ICON, DRAW_ALERT_TEXT, SHOW_ALERT_BTNS (and 2 more)
LOOKUP_ALERT_ID:                                | DSAlertTab lookup helper
        MOVE.L  (DSAlertTab).w,A0               | A0 = alert table base
        MOVE    (A0)+,D1                        | D1 = entry count (post-increment)
        BRA.B   LOOKUP_NEXT                     | drop into scan loop

| ----------------------------------------------------------
| LOOKUP_LOOP - alert table search loop
LOOKUP_LOOP:
        CMP     (A0)+,D0                        | compare ID with table entry
        BEQ.B   LOOKUP_FOUND                    | match - return this entry
        ADDA    (A0)+,A0                        | skip entry data (offset to next)
LOOKUP_NEXT:
        DBF     D1,LOOKUP_LOOP                  | loop through all entries
        MOVEQ.L #0x0,D0                         | not found: D0=0, Z=1
        SUBA.L  A0,A0                           | A0 = nil
        RTS                                     | return with Z flag set (not found)
LOOKUP_FOUND:
        MOVEQ.L #-0x1,D0                        | found: D0=-1, Z=0
        ADDQ.W  #0x2,A0                         | skip past offset word to entry data
        RTS                                     | return with Z flag clear (found)
