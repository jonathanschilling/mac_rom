| TextEdit
|
| Apple source: TextEdit.a (MacSEROM.lst module TEXTEDIT): TEGetText,
| TEInit, TEDispose, TextBox, TESetText, TECalText, TESetSelect, TENew,
| TEUpdate, TEClick, TECopy, TECut, TEDelete, TEActivate, TEDeactivate,
| TEIdle, TEPaste, TEInsert, TEKey, TEScroll, TESetJust, with the internal
| measuring and line-breaking routines. (The automatic scrolling calls
| TEPinScroll, TESelView and TEAutoView are Mac Plus additions.)
|
| TERec (MPW 1.0 TextEdit.h):
| Offset 0: destRect Rect destination rectangle (8 bytes)
| Offset 8: viewRect Rect view rectangle (8 bytes)
| Offset 16: selRect Rect selection rectangle
| Offset 24: lineHeight INTEGER line height in pixels
| Offset 26: fontAscent INTEGER font ascent
| Offset 28: selPoint Point selection point
| Offset 32: selStart INTEGER start of selection
| Offset 34: selEnd INTEGER end of selection
| Offset 36: active INTEGER active flag
| Offset 38: wordBreak ProcPtr word break procedure
| Offset 42: clikLoop ProcPtr click loop procedure
| Offset 46: clickTime LongInt time of last click
| Offset 50: clickLoc INTEGER location of last click
| Offset 52: caretTime LongInt time of last caret blink
| Offset 56: caretState INTEGER caret on/off state
| Offset 58: just INTEGER justification (0=left, 1=center, -1=right)
| Offset 60: teLength INTEGER length of text
| Offset 62: hText Handle handle to text
| Offset 66: recalBack INTEGER reserved
| Offset 68: recalLines INTEGER reserved
| Offset 70: clikStuff INTEGER reserved
| Offset 72: crOnly INTEGER carriage return only flag
| Offset 74: txFont INTEGER text font
| Offset 76: txFace Style text face
| Offset 78: txMode INTEGER text transfer mode
| Offset 80: txSize INTEGER text size
| Offset 82: inPort GrafPtr port for drawing
| Offset 86: highHook ProcPtr highlighting hook
| Offset 90: caretHook ProcPtr caret drawing hook
| Offset 94: nLines INTEGER number of lines
| Offset 96: lineStarts[] INTEGER[] start offset of each line
|
| References:
| Inside Macintosh Vol I, Ch 12: TextEdit

| ----------------------------------------------------------
| TEGetText -- _TEGetText ($A9CB).
| Returns the text Handle of a TERec.
TEGetText:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        MOVE.L  teTextH(A3),(A2)                | store TE text handle in caller's slot
        BRA.W   TECALTEXT_EXIT                  | -> common TE epilog

| ----------------------------------------------------------
| TEInit -- _TEInit ($A9CC).
| Initialize TextEdit globals: allocate empty scrap handle and
| install default TEDoText / TERecal / TEWdBreak hooks.
TEInit:
        MOVEQ.L #0x0,D0                         | zero-length handle
        MOVE    D0,(TEScrpLength).w             | clear TE scrap length
        _NewHandle                              | allocate empty scrap handle
        MOVE.L  A0,(TEScrpHandle).w             | save TE scrap handle
        LEA     XTRIMMEASURE_OK_CONT_3(PC),A0   | default text drawing/measuring
        MOVE.L  A0,(TEDoText).w                 | install TEDoText hook
        LEA     TEFINDWORD_CONT_4_CONT_9(PC),A0 | default line recalculation
        MOVE.L  A0,(TERecal).w                  | install TERecal hook
        LEA     TEFINDWORD_CONT_4_CONT(PC),A0   | default word break detection
        MOVE.L  A0,(TEWdBreak).w                | install TEWdBreak hook
        RTS                                     | return from default hook installation

| ----------------------------------------------------------
| TEDispose -- _TEDispose ($A9CD).
| Dispose a TERec handle (its text handle and the TERec itself).
TEDispose:
        MOVEM.L D2-D7/A2-A4,-(SP)               | save registers
        MOVE.L  0x28(SP),A4                     | A4 = TE handle param
        MOVE.L  (A4),A3                         | A3 = TERec dereferenced
        MOVE.L  teTextH(A3),A0                  | A0 = text handle
        _DisposeHandle                          | dispose text
        MOVE.L  A4,A0                           | A0 = TE handle
        _DisposeHandle                          | dispose TERec itself
        MOVEQ.L #0x4,D0                         | 4 param bytes
        BRA.B   TEXTBOX_EXIT                    | -> common TE exit
| ----------------------------------------------------------
|
| _TextBox ($A9CE): draw text in a rectangle with the given justification
| Pascal: PROCEDURE TextBox(text: Ptr; length: LongInt; box: Rect;
|                           just: INTEGER);
| Erases box, creates a temporary TERec with destRect = viewRect = box
| (TENew) and sets its just; unless length = 0, sets the text
| (TESetText) and draws it (TEUpdate(box)); then disposes the TERec.
|
TextBox:
        MOVEM.L D2-D7/A2-A4,-(SP)               | save regs
        SUBQ.W  #0x4,SP                         | space for TENew result
        MOVE.L  0x2E(SP),-(SP)                  | push @box (destRect)
        MOVE.L  (SP),-(SP)                      | dup for viewRect
        MOVE.L  (SP),-(SP)                      | dup for EraseRect
        _EraseRect                              | clear the box area
        _TENew                                  | create temporary TERec
        MOVE.L  (SP)+,A4                        | A4 = TEHandle
        MOVE.L  (A4),A0                         | A0 = dereferenced TERec
        MOVE    0x28(SP),0x3A(A0)               | set TERec.just from param
        MOVE.L  0x2E(SP),D0                     | D0 = text length param
        BEQ.B   TEXTBOX_NO                      | empty -> skip text setup
        MOVE.L  0x32(SP),-(SP)                  | push text ptr param
        MOVE.L  D0,-(SP)                        | push text length
        MOVE.L  A4,-(SP)                        | push TEHandle
        _TESetText                              | set the text content
        MOVE.L  0x2A(SP),-(SP)                  | push @box (update rect)
        MOVE.L  A4,-(SP)                        | push TEHandle
        _TEUpdate                               | draw all text lines
TEXTBOX_NO:
        MOVE.L  A4,-(SP)                        | push TEHandle
        _TEDispose                              | dispose temporary TERec
        MOVEQ.L #0xE,D0                         | strip 14 param bytes
TEXTBOX_EXIT:
        BRA.B   TECALTEXT_EXIT_3                | share TE common epilog

| ----------------------------------------------------------
| TESetText -- _TESetText ($A9CF).
| Replaces the text content of a TERec with a Ptr+length copy.
TESetText:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state (A3, A2=params)
        MOVE.L  (A2)+,D0                        | D0 = text length
        MOVE    D0,teSelStart(A3)               | selStart = length (cursor at end)
        MOVE    D0,teSelEnd(A3)                 | selEnd = length
        MOVE    D0,teLength(A3)                 | teLength = new length
        MOVE.L  (A2)+,A0                        | A0 = text pointer
        MOVE.L  teTextH(A3),A1                  | A1 = text handle
        BCLR    #0x7,(A1)                       | unlock text handle before resize
        _PtrToXHand                             | copy text to handle (resizes)
        MOVE.L  A4,-(SP)                        | push TE handle
        _TECalText                              | recalculate line breaks
TESETTEXT_EXIT:
        BRA.W   TEINSERT_EXIT                   | share TE epilog

| ----------------------------------------------------------
| TECalText -- _TECalText ($A9D0).
| Recalculate line breaks for the text.
TECalText:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        MOVE.L  teSelStart(A3),-(SP)            | save selStart/selEnd
        CLR     teSelStart(A3)                  | clear selStart (for full recalc)
        MOVE    #-0x7FFE,D7                     | flag: full recalculation needed
        CLR.L   0x60(A3)                        | clear line cache
        BSR.W   TEFINDWORD_CONT_4_CONT_8        | recalculate all line breaks
        MOVE.L  (SP)+,teSelStart(A3)            | restore selStart/selEnd
TECALTEXT_EXIT:
        MOVEQ.L #0x4,D0                         | strip 4 param bytes
TECALTEXT_EXIT_2:
        MOVE.L  0x32(SP),A4                     | A4 = TE handle from saved frame
        MOVE.L  (A4),A3                         | A3 = dereferenced TE record
        MOVE    D0,D4                           | D4 = strip count (saved)
        MOVE.L  teTextH(A3),A0                  | A0 = text handle
        BCLR    #0x7,(A0)                       | unlock text handle
        MOVE.L  (SP),-(SP)                      | dup saved clip region
        _SetClip                                | restore caller's clip
        _DisposeRgn                             | dispose temp clip region
        MOVE.B  (SP)+,(A4)                      | restore master ptr lock byte
        _SetPort                                | restore caller's grafPort
        MOVE    D4,D0                           | reload strip count
TECALTEXT_EXIT_3:
        MOVEM.L (SP)+,D2-D7/A2-A4               | restore working registers
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA.W  D0,SP                           | SP += D0
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| TESetSelect -- _TESetSelect ($A9D1).
| Set the current selection range (selStart, selEnd) and
| re-highlight.
TESetSelect:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        BSR.W   P_TERECAL_CONT_3                | erase old caret
        BSR.W   TEUPDATE_CONT_2                 | erase old hilite
        MOVE.L  (A2)+,teSelStart(A3)            | selEnd (long): low word -> teSelEnd (+$22)
        MOVE.L  (A2)+,30(A3)                    | selStart: low word -> teSelStart, high -> teSelPoint.h
        BSR.W   TETEXTHAND_LOCK_LEN             | relock text handle, refresh teLength
        BSR.W   P_TERECAL_NO_3                  | redraw caret
        BSR.W   TEUPDATE_CONT_2                 | redraw hilite
        BRA.B   TESETTEXT_EXIT                  | share TE epilog

| ----------------------------------------------------------
| TENew -- _TENew ($A9D2).
| Allocate + initialize a new TERec handle from destRect/viewRect.
TENew:
        MOVEM.L D2-D7/A2-A4,-(SP)               | save regs
        MOVEQ.L #teRecSize,D0                   | D0 = $68 = base TE record size
        _NewHandleClear                         | allocate + zero TE handle
        MOVE.L  A0,A4                           | A4 = TE handle
        BSET    #0x7,(A4)                       | lock TE master pointer
        MOVE.L  (A4),A3                         | A3 = dereferenced TE record
        MOVEQ.L #0x0,D0                         | zero-length text handle
        _NewHandle                              | allocate empty text handle
        MOVE.L   A0,62(A3)                      | store hText handle in TERec.hText
        LEA.L     (A3),A0                       | A0 = TERec.destRect base
        MOVE.L  0x2C(SP),A2                     | A2 = destRect ptr param
        MOVE.L  (A2)+,(A0)+                     | copy destRect topLeft
        MOVE.L  (A2)+,(A0)+                     | copy destRect botRight
        MOVE.L  0x28(SP),A2                     | A2 = viewRect ptr param
        MOVE.L  (A2)+,(A0)+                     | copy viewRect topLeft
        MOVE.L  (A2)+,(A0)+                     | copy viewRect botRight
        SUBQ.W  #0x8,SP                         | space for FontInfo struct
        MOVE.L  SP,-(SP)                        | push ptr for GetFontInfo
        _GetFontInfo                            | get current font metrics
        MOVE    (SP)+,D0                        | D0 = ascent
        MOVE    D0,26(A3)                       | set TERec.fontAscent
        ADD     (SP)+,D0                        | D0 += descent
        ADDQ.W  #0x2,SP                         | skip widMax field
        ADD     (SP)+,D0                        | D0 += leading = lineHeight
        MOVE    D0,24(A3)                       | store TERec.lineHeight
        MOVE.L  (A5),A2                         | A2 = QD globals base
        MOVE.L  (A2),A2                         | A2 = current grafPort ptr
        MOVE.L  A2,teInPort(A3)                 | set TERec.inPort
        MOVE.L  0x44(A2),0x4A(A3)               | copy port txFont/txFace
        MOVE.L  0x48(A2),teMode(A3)             | copy port txMode/txSize
        MOVE.L  (TEWdBreak).w,teWordBreak(A3)   | install default wordBreak hook
        BCLR    #0x7,(A4)                       | unlock TE master pointer
        MOVE.L  A4,0x30(SP)                     | return TE handle to caller
        MOVEQ.L #0x8,D0                         | strip 8 param bytes
        BRA.W   TECALTEXT_EXIT_3                | share TE epilog

| ----------------------------------------------------------
| TEUpdate -- _TEUpdate ($A9D3).
| Redraw text within the update rectangle.
TEUpdate:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        MOVE.L  (A2)+,A0                        | A0 = update rect ptr
        MOVE    (A0),D0                         | D0 = top
        MOVE    4(A0),D1                        | D1 = bottom
        BSR.W   XTRIMMEASURE_CONT_6_CONT        | redraw text in range
        BRA.W   TESCROLL_EXIT                   | -> common TE exit

| ----------------------------------------------------------
| TEUPDATE_CONT -- expand single click position D6 to word range D0-D1.
| On entry D2 holds the double-click flag (set by TEClick double-click
| detection); when zero, returns D0=D1=D6 (single char). When set,
| calls TEDELETE_CONT_CONT_3 to expand to word boundaries. Plus 968
| uses D5 (long, BPL test); classic uses D2 (byte, BEQ test).
TEUPDATE_CONT:
        MOVE    D6,D0                           | D0 = D6 (initial: single char)
        MOVE    D6,D1                           | D1 = D6
        TST.B   D2                              | double-click flag set?
        BEQ.B   TEUPDATE_EXIT                   | no -> return single char range
        BSR.W   TEDELETE_CONT_CONT_3            | expand D0-D1 to word boundaries
TEUPDATE_EXIT:
        RTS                                     | shared with TEUPDATE_CONT_2 bail

| ----------------------------------------------------------
| TEUPDATE_CONT_2
| Called during boot.
TEUPDATE_CONT_2:                                | call subroutine via A0
        TST.B   teActive(A3)                    | is TE record active?
        BEQ.B   TEUPDATE_EXIT                   | no -> nothing to highlight
        MOVEM   teSelStart(A3),D3-D4            | D3=teSelStart, D4=teSelEnd
        MOVEQ.L #0x1,D7                         | D7=1: highlight/unhighlight mode
        BRA.W   XTRIMMEASURE_OK_CONT_2          | -> draw/erase selection hilite

| ----------------------------------------------------------
| TEClick -- _TEClick ($A9D4).
| Process a mouse click in the TE text area: hit-test, set
| selection, track mouse for double-click and drag-select.
TEClick:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        MOVE.L  0x38(SP),28(A3)                 | save click point in teSelPoint (+$1C)
        BSR.W   TECLICK_CONT_5                  | hit-test point -> D6 = char offset
        BSR.W   P_TERECAL_CONT_3                | erase existing caret/hilite
        SUBQ.W  #0x4,SP                         | space for TickCount result
        _TickCount                              | get current tick count
        MOVE.L  (SP),D0                         | D0 = current ticks
        SUB.L   teClikTime(A3),D0               | D0 = elapsed since last click
        CMP.L   (DoubleTime).w,D0               | within double-click interval?
        SLE     D2                              | set if <=: D2
        CMP     teClikLoc(A3),D6                | same char position as last click?
        SEQ     D1                              | D1 = $FF if same position
        AND.B   D1,D2                           | D2 = double-click (time AND position)
        MOVE    D6,teClikLoc(A3)                | save click position for next time
        MOVE.L  (SP)+,teClikTime(A3)            | save click time
        TST.B   0x36(SP)                        | extend flag (shift-click)?
        BEQ.B   TECLICK_NO_2                    | no: start fresh selection
        MOVEM   teSelStart(A3),D0-D1            | D0=teSelStart, D1=teSelEnd
        CMP     D6,D0                           | click before selStart?
        BCC.B   TECLICK_NO                      | click <= selStart: anchor at selEnd
        MOVE    D0,A2                           | A2 = anchor start = selStart
        MOVE    D0,A4                           | A4 = anchor end = selStart
        BRA.B   TECLICK_CONT                    | update with new position
TECLICK_NO:
        MOVE    D1,A2                           | A2 = anchor at selEnd
        MOVE    D1,A4                           | A4 = anchor at selEnd
TECLICK_CONT:
        MOVE    D6,D5                           | D5 = last tracked click offset
        BRA.B   TECLICK_CONT_2                  | update selection highlighting
TECLICK_NO_2:
        BSR.B   TEUPDATE_CONT_2                 | unhighlight current selection
        BSR.B   TEUPDATE_CONT                   | get word bounds if double-click
        MOVEM   D0-D1,teSelStart(A3)            | set teSelStart/teSelEnd
        MOVE    D0,A2                           | A2 = selection anchor start
        MOVE    D1,A4                           | A4 = selection anchor end
        MOVE    D6,D5                           | D5 = updated tracking position
        MOVE.B  0x46(A3),0x47(A3)               | save teLftClick to teLftCaret
        BSR.W   P_TERECAL_NO_3                  | set caret state if insertion point
        BSR.B   TEUPDATE_CONT_2                 | set up LINK frame, save regs
TECLICK_LOOP:
        MOVE.L  teClikProc(A3),D0               | D0 = click loop proc
        BEQ.B   TECLICK_EMPTY                   | nil -> use default WaitMouseUp
        MOVE.L  D0,A0                           | A0 = click loop proc
        JSR     (A0)                            | call subroutine via A0
        BEQ.B   TECLICK_CONT_4                  | app says stop: end tracking
TECLICK_EMPTY:
        CLR     -(SP)                           | space for WaitMouseUp result
        _WaitMouseUp                            | wait for mouse movement or release
        TST     (SP)+                           | still tracking?
        BEQ.B   TECLICK_CONT_4                  | mouse released: end tracking
        PEA.L     28(A3)                        | push ptr to teSelPoint
        _GetMouse                               | read current mouse position
        BSR.B   TECLICK_CONT_5                  | walk tree -> D6 = line index
        CMP     D6,D5                           | same line as last click?
        BEQ.B   TECLICK_LOOP                    | yes -> keep waiting
        BSR.W   P_TERECAL_CONT_3                | hide caret before hilite update
TECLICK_CONT_2:
        BSR.W   TEUPDATE_CONT                   | expand to word bounds if dbl-click
        LEA.L     teSelEnd(A3),A0               | A0 = &0x22(A3)
        CMPA.W  D6,A4                           | click before anchor end?
        BCS.B   TECLICK_OK                      | yes: extending forward
        MOVE    -(A0),D3                        | D3.W = old teSelStart
        MOVE    D0,(A0)+                        | teSelStart = new start
        MOVE    D0,D4                           | D4.W = new start
        SWAP    D3                              | D3: old selStart in high word
        SWAP    D4                              | D4: new start in high word
        MOVE    A4,D3                           | D3.W = anchor position
        MOVE    (A0)+,D4                        | D4.W = old teSelEnd
        MOVE    A4,-(A0)                        | teSelEnd = anchor
        BRA.B   TECLICK_CONT_3                  | XOR hilite for both ranges

| ----------------------------------------------------------
| TECLICK_OK
TECLICK_OK:
        CMPA.W  D6,A2                           | click still within anchor range?
        BHI.B   TECLICK_OK_2                    | yes -> no hilite change needed
        MOVE    (A0)+,D3                        | D3.W = old teSelEnd
        MOVE    D1,-(A0)                        | teSelEnd = new end
        MOVE    D1,D4                           | D4.W = new end
        SWAP    D3                              | D3: old selEnd in high word
        SWAP    D4                              | D4: new end in high word
        MOVE    -(A0),D3                        | D3.W = old teSelStart
        MOVE    A2,D4                           | D4.W = anchor start
        MOVE    A2,(A0)+                        | teSelStart = anchor
TECLICK_CONT_3:
        MOVEQ.L #0x1,D7                         | D7=1: highlight/unhighlight mode
        BSR.W   XTRIMMEASURE_OK_CONT_2          | XOR hilite for first changed range
        SWAP    D3                              | swap to second range pair
        SWAP    D4                              | swap to second range pair
        BSR.W   XTRIMMEASURE_OK_CONT_2          | XOR hilite for second changed range
TECLICK_OK_2:
        MOVE    D6,D5                           | D5 = updated tracking position
        BRA.B   TECLICK_LOOP                    | continue tracking loop
TECLICK_CONT_4:
        BSR.W   P_TERECAL_NO_3                  | set caret state if insertion point
        MOVEQ.L #0xA,D0                         | strip 10 param bytes
        BRA.W   TECALTEXT_EXIT_2                | share TE epilog

| TECLICK_CONT_5 -- convert point to char offset -> D6.
| ----------------------------------------------------------
| TECLICK_CONT_5
TECLICK_CONT_5:
        MOVE    28(A3),D0                       | D0 = click vertical coord
        BSR.W   XTRIMMEASURE_CONT_6             | convert to line number -> D0
        BGE.B   TECLICK_CONT_6                  | beyond last line -> selEnd
        ADD     D0,D0                           | word offset into lineStarts
        BLT.B   TECLICK_CONT_5_CONT_2           | before first line: offset 0
        MOVEM   0x60(A3,D0.W),D3-D4             | D3/D4 = lineStarts[line], lineStarts[line+1]
        MOVEQ.L #0x0,D7                         | D7=0: pixel-to-char mode
        BSR.B   XTRIMMEASURE_OK_CONT_2          | find char offset at click.h
        MOVE    D0,D6                           | D6 = character offset at click
        RTS                                     | return measured offset
TECLICK_CONT_6:
        MOVE    teLength(A3),D6                 | click past end: D6 = teLength
        RTS                                     | return offset teLength
TECLICK_CONT_5_CONT_2:
        MOVEQ.L #0x0,D6                         | click before first line: offset 0
        RTS                                     | return offset 0
TECLICK_CONT_5_CONT_3:
        MOVE    24(A3),D0                       | D0 = lineHeight
        ADD     D0,16(A3)                       | 16(A3) += D0
        ADD     D0,20(A3)                       | 20(A3) += D0
        ADD     D0,0x30(A2)                     | 0x30(A2) += D0
        RTS                                     | return from line advance
TECLICK_CONT_5_CONT_4:
        MOVE    D3,-(SP)                        | save D3 (start char)
        MOVE    (A4),D3                         | D3 = next-line start char
        BSR.B   TECLICK_CONT_5_CONT_7           | measure line width -> D0
        MOVE    (SP)+,D3                        | restore D3
        MOVE    6(A3),D1                        | D1 = destRect.right
        SUB     2(A3),D1                        | D1 = destRect width
        SUB.W    D0,D1                          | D1 = slack pixels (width - text)
        SUBQ.W   #0x1,D1                        | leave 1px insertion margin
        TST     teJust(A3)                      | justification mode?
        BEQ.B   TECLICK_CONT_5_CONT_6           | left-justify: no shift
        BMI.B   TECLICK_CONT_5_CONT_5           | right-justify: full shift
        ASR     #0x1,D1                         | center-justify: half shift
TECLICK_CONT_5_CONT_5:
        ADD     D1,0x32(A2)                     | shift line origin by D1
TECLICK_CONT_5_CONT_6:
        ADDQ.W  #0x1,0x32(A2)                   | skip leading pixel margin
        RTS                                     | return from line origin compute
TECLICK_CONT_5_CONT_7:
        MOVE    D3,-(SP)                        | save D3 (line end char)
XTRIMMEASURE_OK:
        SUBQ.W  #0x1,D3                         | trim trailing char
        CMP     D3,D6                           | at line start?
        BEQ.B   XTRIMMEASURE_OK_CONT            | yes: empty line, exit
        MOVE    D3,A1                           | A1 = current end char
        BSR.W   TEFINDWORD_CONT_4               | test trailing char (space/CR)
        BNE.B   XTRIMMEASURE_OK                 | trim more trailing whitespace
XTRIMMEASURE_OK_CONT:
        ADDQ.W  #0x1,D3                         | restore last visible char
        BSR.B   XTRIMMEASURE_OK_OK              | measure visible width -> D0
        MOVE    (SP)+,D3                        | restore D3
        RTS                                     | return measured line width
XTRIMMEASURE_OK_OK:
        SUBQ.W  #0x2,SP                         | space for TextWidth result
        MOVE.L  teTextH(A3),A0                  | A0 = text handle
        MOVE.L  (A0),-(SP)                      | push text ptr
        MOVE    D6,-(SP)                        | push start offset
        MOVE    D3,-(SP)                        | push end offset
        SUB     D6,(SP)                         | length = end - start
        _TextWidth                              | measure pixel width
        MOVE    (SP)+,D0                        | D0 = measured width
        RTS                                     | return text width
| Called by: TECLICK_CONT_3, TEUPDATE_CONT_2, TECLICK_CONT_5, TEDELETE_CONT_NO, P_TERECAL_CONT_4 (and 1 more)
XTRIMMEASURE_OK_CONT_2:
        MOVE.L  (TEDoText).w,-(SP)              | push TEDoText hook for jump
        RTS                                     | jump via TEDoText hook
XTRIMMEASURE_OK_CONT_3:
        MOVEM.L D2-D7/A2-A4,-(SP)               | save working registers
        MOVE.L  (A5),A2                         | A2 = QD globals base
        MOVE.L  (A2),A2                         | A2 = current grafPort ptr
        MOVE    (A3),D0                         | D0 = destRect.top
        MOVE    D0,16(A3)                       | set selRect.top
        ADD     24(A3),D0                       | add lineHeight
        MOVE    D0,20(A3)                       | set selRect.bottom
        MOVE.L  (A3),0x30(A2)                   | set port pen at destRect.topLeft
        MOVE    26(A3),D0                       | D0 = fontAscent
        ADD     D0,0x30(A2)                     | 0x30(A2) += D0
        CMP     D3,D4                           | D4 < D3 (range reversed)?
        BCC.B   XTRIMMEASURE_OK_CONT_4          | ordered: continue
        EXG     D4,D3                           | swap to make D3<=D4
XTRIMMEASURE_OK_CONT_4:
        LEA.L     0x60(A3),A4                   | A4 -> lineStarts[0]
XTRIMMEASURE_OK_CONT_5:
        MOVE    (A4)+,D6                        | D6 = current line start
        MOVE    (A4),D0                         | D0 = next line start
        CMP     teLength(A3),D0                 | past end of text?
        BCC.B   XTRIMMEASURE_OK_CONT_7          | yes: handle last line
        CMP     D0,D3                           | D3 before next line?
        BCS.B   XTRIMMEASURE_OK_NO              | yes: D3 is on this line
        BNE.B   XTRIMMEASURE_OK_CONT_6          | past line: skip ahead
        CMPI    #-0x2,D7                        | caret-mode (D7=-2)?
        BNE.B   XTRIMMEASURE_OK_CONT_6          | no: skip line
        TST.B   0x47(A3)                        | teLftCaret set?
        BEQ.B   XTRIMMEASURE_OK_NO              | no: caret on prev line
XTRIMMEASURE_OK_CONT_6:
        BSR.W   TECLICK_CONT_5_CONT_3           | advance pen down one line
        BRA.B   XTRIMMEASURE_OK_CONT_5          | loop to next line
XTRIMMEASURE_OK_CONT_7:
        CMPI.B  #0xFE,D7                        | caret-mode tail (D7=-2)?
        BNE.B   XTRIMMEASURE_OK_NO              | no: handle as range start
        MOVE.L  teTextH(A3),A0                  | hText handle
        MOVE.L  (A0),A0                         | dereference to text ptr
        MOVE.B  -0x1(A0,D0.W),D1                | D1 = last char before selection
        CMPI.B  #0xD,D1                         | compare D1 vs 0xD (CR)
        BNE.B   XTRIMMEASURE_OK_NO              | no CR: caret on prev line
        CMP     D3,D0                           | caret at exact end?
        BNE.B   XTRIMMEASURE_OK_NO              | no: prev line
        BSR.W   TECLICK_CONT_5_CONT_3           | advance pen to next line
        MOVE    (A4),D6                         | D6 = next line start
        BRA.B   XTRIMMEASURE_OK_CONT_8          | skip width measure
XTRIMMEASURE_OK_NO:
        BSR.W   XTRIMMEASURE_OK_OK              | measure width D6..D3 -> D0
        ADD     D0,0x32(A2)                     | advance pen by D0
XTRIMMEASURE_OK_CONT_8:
        BSR.W   TECLICK_CONT_5_CONT_4           | compute line origin (justify)
        MOVE    D3,D6                           | D6 = D3 (start of range)
        BRA.W   XTRIMMEASURE_OK_CONT_16         | enter measure/draw loop
XTRIMMEASURE_OK_CONT_9:
        CMP     (A4),D6                         | at next line start?
        BCS.B   XTRIMMEASURE_OK_CONT_10         | no: stay on this line
        ADDQ.W  #0x2,A4                         | advance lineStarts ptr
        MOVE    0x30(A2),D0                     | D0 = pen.v
        CMP     12(A3),D0                       | past viewRect bottom?
        BGT.W   XTRIMMEASURE_OK_OK_2            | yes: stop drawing
        BSR.W   TECLICK_CONT_5_CONT_3           | advance pen down one line
        MOVE    2(A3),0x32(A2)                  | reset pen.h to destRect.left
        BSR.W   TECLICK_CONT_5_CONT_4           | recompute line origin
XTRIMMEASURE_OK_CONT_10:
        MOVE    0x32(A2),18(A3)                 | set selRect.left = pen.h
        MOVE    0x32(A2),(scratch8).w           | save pen.h to scratch
        TST     D7                              | dispatch on mode
        BNE.B   XTRIMMEASURE_OK_NO_2            | not measure: continue
        MOVE    D6,D3                           | measure mode: D3 = D6
        ADDQ.W  #0x1,D3                         | advance one char
        BRA.B   XTRIMMEASURE_OK_CONT_12         | measure to D3
XTRIMMEASURE_OK_NO_2:
        CMP     (A4),D4                         | D4 within this line?
        BCC.B   XTRIMMEASURE_OK_CONT_11         | no: clamp to line end
        MOVE    D4,D3                           | yes: D3 = D4
        BRA.B   XTRIMMEASURE_OK_CONT_12         | measure to D3
XTRIMMEASURE_OK_CONT_11:
        MOVE    (A4),D3                         | clamp D3 to line end
XTRIMMEASURE_OK_CONT_12:
        BSR.W   XTRIMMEASURE_OK_OK              | measure width D6..D3 -> D0
        MOVE    D0,D2                           | D2 = measured width
        ADD     0x32(A2),D0                     | D0 = right edge x
        MOVE    D0,D5                           | D5 = right edge
        MOVE    D0,-(SP)                        | save right edge
        MOVE    D0,22(A3)                       | set selRect.right
        CMP     -2(A4),D6                       | at start of line?
        BNE.B   XTRIMMEASURE_OK_NO_3            | no: keep selRect.left
        MOVE    #-0x7FFE,18(A3)                 | extend selRect.left to -32766
        ADD     D5,D5                           | D5 *= 2
        SUB     (scratch8).w,D5                 | D5 -= start pen.h
        SUB     D2,D5                           | D5 -= width (= 2*right - origin)
XTRIMMEASURE_OK_NO_3:
        CMP     (A4),D3                         | at end of line?
        BNE.B   XTRIMMEASURE_OK_CONT_13         | no: keep selRect.right
        MOVE    #0x7FFE,22(A3)                  | extend selRect.right to 32766
        MOVE.L  teTextH(A3),A0                  | A0 = text handle
        MOVE.L  (A0),A0                         | A0 = text data ptr
        CMPI.B  #0xD,0(A0,D6.W)                 | first char is CR?
        BNE.B   XTRIMMEASURE_OK_CONT_13         | no: skip
        MOVE    #0x7000,D5                      | set "wraps" flag in D5
XTRIMMEASURE_OK_CONT_13:                        | jump via A0
        TST     D7                              | dispatch on mode
        BPL.B   XTRIMMEASURE_OK_CONT_14         | positive: not draw
        PEA.L     16(A3)                        | push selRect for EraseRect
        _EraseRect                              | erase selRect first
        MOVEA.L teTextH(A3),A0                  | A0 = hText (text handle)
        MOVE.L  (A0),-(SP)                      | push dereferenced text ptr
        MOVE    D6,-(SP)                        | push start char index
        MOVE    D3,-(SP)                        | push end char index
        SUB     D6,(SP)                         | (SP) -= D6
        _DrawText                               | draw text from D6 to D3
XTRIMMEASURE_OK_CONT_14:
        MOVE    D3,D6                           | advance D6 = D3
        MOVE    (SP)+,0x32(A2)                  | restore pen.h to right edge
        TST     D7                              | dispatch on mode
        BLE.B   XTRIMMEASURE_OK_CONT_15         | not highlight mode
        MOVE.L  teHighHook(A3),D0               | D0 = custom hilite hook
        BSR.B   XTRIMMEASURE_CONT_7             | invert selRect
XTRIMMEASURE_OK_CONT_15:
        TST     D7                              | dispatch on mode
        BNE.B   XTRIMMEASURE_OK_CONT_16         | not hit-test
        CLR     -(SP)                           | space for PtInRect result
        MOVE.L  28(A3),-(SP)                    | push teSelPoint
        PEA.L     16(A3)                        | push selRect
        _PtInRect                               | point in this char rect?
        TST.B   (SP)+                           | test result
        BEQ.B   XTRIMMEASURE_OK_CONT_16         | no: try next
        SF      0x46(A3)                        | teLftClick = false (right side)
        SUB     30(A3),D5                       | D5 -= teSelPoint.h
        SUB     30(A3),D5                       | D5 -= again (margin check)
        ADD     (scratch8).w,D5                 | D5 += saved pen.h
        BLT.B   XTRIMMEASURE_OK_OK_2            | click on right half: keep
        SUBQ.W  #0x1,D6                         | click on left half: D6--
        ST      0x46(A3)                        | teLftClick = true (left side)
        BRA.B   XTRIMMEASURE_OK_OK_2            | return found offset
XTRIMMEASURE_OK_CONT_16:
        CMP     D4,D6                           | past end of range?
        BCC.B   XTRIMMEASURE_OK_CONT_17         | yes: done
        CMP     teLength(A3),D6                 | past end of text?
        BCS.W   XTRIMMEASURE_OK_CONT_9          | no: continue
XTRIMMEASURE_OK_CONT_17:
        MOVEQ.L #0x0,D6                         | return D0=0 (not found)
XTRIMMEASURE_OK_OK_2:
        MOVE    D6,D0                           | D0 = char offset (return)
        MOVE.L  A2,A0                           | A0 = grafPort ptr
        MOVEM.L (SP)+,D2-D7/A2-A4               | restore working registers
        RTS                                     | return from TEDoText

| ----------------------------------------------------------
| XTRIMMEASURE_CONT_7
| Called during boot.
XTRIMMEASURE_CONT_7:
        PEA.L     16(A3)                        | push selection rect for hilite
        BEQ.B   XTRIMMEASURE_NO_5               | D0=0 (no hook) -> use InverRect
        MOVE.L  D0,A0                           | A0 = custom highlight hook
        JMP     (A0)                            | call hook with rect on stack
XTRIMMEASURE_NO_5:
        _InvertRect                             | default: XOR-invert selRect
        RTS                                     | return from highlight
XTRIMMEASURE_CONT_12:
        MOVE.L  (SP)+,A0                        | pop return address
        MOVEM.L D2-D7/A2-A4,-(SP)               | save working registers
        SUBA.W  #0xA,SP                         | SP -= #0xA
        MOVE.L  A0,-(SP)                        | re-push return address
        MOVE.L  0x36(SP),A4                     | A4 = TEHandle from caller
        MOVE.L  (A4),A3                         | A3 = dereferenced TERec
        MOVE.B  (A4),8(SP)                      | save handle lock byte
        PEA.L     10(SP)                        | push ptr for GetPort
        _GetPort                                | save current grafPort
        BSET    #0x7,(A4)                       | lock TE master pointer
        MOVE.L  teInPort(A3),A2                 | A2 = TE's grafPort
        MOVE.L  A2,-(SP)                        | push port for SetPort
        _SetPort                                | switch to TE's grafPort
        SUBQ.W  #0x4,SP                         | space for NewRgn result
        _NewRgn                                 | allocate scratch region
        MOVE.L  (SP),8(SP)                      | save scratch region in frame
        MOVE.L  (SP),-(SP)                      | push region for GetClip
        _GetClip                                | save current clip into region
        PEA.L     8(A3)                         | push viewRect address
        _ClipRect                               | set clip = TE viewRect
        MOVE.L  28(A2),-(SP)                    | push current port clip rgn
        MOVE.L  (SP),-(SP)                      | dup as dest for SectRgn
        _SectRgn                                | intersect with viewRect
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  (A0),A0                         | A0 = current grafPort
        MOVE.L  0x4A(A3),0x44(A0)               | copy TE txFont/txFace to port
        MOVE.L  teMode(A3),0x48(A0)             | copy TE txMode/txSize to port
TETEXTHAND_LOCK_LEN:                            | lock text handle + cache length
        MOVE.L  teTextH(A3),A0                  | A0 = hText (text handle)
        _HLock                                  | lock it down
        _GetHandleSize                          | D0 = text length
        MOVE    D0,teLength(A3)                 | store in teLength
        MOVE    teSelEnd(A3),D1                 | D1 = selEnd
        SUB     D0,D1                           | D1 = selEnd - length
        BLS.B   XTRIMMEASURE_CONT_7_OK          | selEnd <= length -> OK
        MOVE    D0,teSelEnd(A3)                 | clamp selEnd to text length
XTRIMMEASURE_CONT_7_OK:
        MOVE    teSelStart(A3),D1               | D1 = selStart
        SUB     teSelEnd(A3),D1                 | D1 = selStart - selEnd
        BLS.B   XTRIMMEASURE_CONT_7_OK_2        | selStart <= selEnd -> OK
        SUB     D1,teSelStart(A3)               | clamp selStart to selEnd
XTRIMMEASURE_CONT_7_OK_2:
        BSR.B   XTRIMMEASURE_CONT_15            | normalize: ensure selStart <= selEnd
        LEA.L     0x3A(SP),A2                   | A2 -> caller's params on stack
        RTS                                     | return from selection range normalization

| ----------------------------------------------------------
| XTRIMMEASURE_CONT_15
| Called during boot (2,779 times in 30s trace).
XTRIMMEASURE_CONT_15:
        LEA.L     teSelStart(A3),A2             | A2 -> teSelStart (offset 0x20)
        MOVE.L  (A2),D0                         | D0 = selStart.W | selEnd.W
        CMP     (A2),D0                         | compare selEnd (D0.W) with selStart
        BCC.B   XTRIMMEASURE_OK_6               | selEnd >= selStart -> OK
        SWAP    D0                              | swap selStart and selEnd
        MOVE.L  D0,(A2)                         | store normalized pair
XTRIMMEASURE_OK_6:
        RTS                                     | return to caller (@ $F8BC)

| ----------------------------------------------------------
| TECopy -- _TECopy ($A9D5).
| Copy selection to TEScrap. Doesn't modify the TERec.
TECopy:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        BSR.B   XTRIMMEASURE_CONT_15            | A2 -> teSelStart, D0.W = selEnd (sorted)
        SUB     (A2),D0                         | D0 = selEnd - selStart
        MOVE    D0,(TEScrpLength).w             | TEScrpLength = sel length
        MOVE.L  teTextH(A3),A0                  | A0 = text handle
        MOVE.L  (A0),A0                         | A0 = text pointer
        ADDA.W  (A2),A0                         | A0 += selStart
        MOVE.L  (TEScrpHandle).w,A1             | A1 = TEScrpHandle
        MOVEQ.L #0x0,D0                         | zero-extend length
        MOVE    (TEScrpLength).w,D0             | D0 = sel length (re-read)
        _PtrToXHand                             | copy selection to scrap
TECOPY_EXIT:
        BRA.W   TECALTEXT_EXIT                  | share TE common epilog

| ----------------------------------------------------------
| TECut -- _TECut ($A9D6).
| Cut: TECopy + TEDelete.
TECut:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        MOVE.L  A4,-(SP)                        | push TE handle for TECopy
        MOVE.L  A4,-(SP)                        | push TE handle for TEDelete
        _TECopy                                 | copy to TEScrap
        _TEDelete                               | remove from TERec
        BRA.B   TECOPY_EXIT                     | -> common TE epilog

| ----------------------------------------------------------
| TEDelete -- _TEDelete ($A9D7).
| Remove the selection range from the text and recalc lines.
TEDelete:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        BSR.W   P_TERECAL_CONT_3                | hide caret if visible
        BSR.B   TEDELETE_CONT                   | remove selected text
        BSR.B   TEDELETE_CONT_CONT_2            | recalc lines + erase area
        BSR.W   P_TERECAL_NO_3                  | redraw affected lines
        BRA.B   TECOPY_EXIT                     | -> common TE epilog

| TEDELETE_CONT -- remove selected text from buffer.
| ----------------------------------------------------------
| TEDELETE_CONT
TEDELETE_CONT:
        BSR.B   XTRIMMEASURE_CONT_15            | normalize selStart<=selEnd
        MOVE    D0,D7                           | D7 = selEnd
        SUB     (A2),D7                         | D7 = selEnd - selStart
        BEQ.B   TEDELETE_EMPTY                  | empty selection: nothing to do
        SUBQ.L  #0x4,SP                         | space for Munger result
        MOVE.L  teTextH(A3),A0                  | A0 = text handle
        MOVE.L  A0,-(SP)                        | push handle for HUnlock
        _HUnlock                                | unlock text before resize
        MOVE    (A2),-(SP)                      | push offset = selStart
        CLR     -(SP)                           | zero-extend offset
        CLR.L   -(SP)                           | ptr1 = nil (no search)
        MOVE    D7,-(SP)                        | push len1 = selection length
        CLR     -(SP)                           | zero-extend len
        CLR.L   -(SP)                           | ptr2 = nil
        CLR.L   -(SP)                           | len2 = 0 (delete only)
        _Munger                                 | delete D7 bytes at selStart
        ADDQ.L  #0x4,SP                         | discard Munger result
        SUB     D7,teLength(A3)                 | teLength(A3) -= D7
        MOVE    (A2)+,(A2)                      | selEnd = selStart (collapse)
TEDELETE_EMPTY:
        RTS                                     | return from delete
TEDELETE_CONT_CONT_2:
        MOVEQ.L #0x0,D2                         | D2 = 0 (start char)
        MOVE    teLength(A3),D4                 | D4 = teLength (end char)
        BSR.W   TEFINDWORD_CONT_4_CONT_8        | recalc lineStarts D2..D4
        MOVE    D2,D3                           | D3 = first changed line
        MOVE    0x5E(A3),D0                     | D0 = nLines
        MULU    24(A3),D0                       | D0 = D0 *u 24(A3)
        LEA.L     20(A3),A0                     | A0 -> selRect.bottom
        MOVE.L  #0x7FF07FF0,(A0)                | store long via (An)
        MOVE.L  (A3),-(A0)                      | set selRect topLeft = destRect
        ADD     D0,(A0)                         | (A0) += D0
        MOVE.L  A0,-(SP)                        | push selRect for EraseRect
        _EraseRect                              | call subroutine via A1
        TST     teJust(A3)                      | teJust <> 0 (centered/right justified)?
        BNE.B   TEDELETE_CONT_NO                | not left-justify: skip
        BSR.B   TEDELETE_CONT_OK                | expand D3 to word start
        MOVE    D0,D3                           | D3 = adjusted start char
        BEQ.B   TEDELETE_CONT_NO                | at start: keep
        SUBQ.W  #0x1,D3                         | step back to word boundary
TEDELETE_CONT_NO:
        MOVEQ.L #-0x1,D7                        | D7=-1: draw mode
        BRA.W   XTRIMMEASURE_OK_CONT_2          | redraw range D3..D4
TEDELETE_CONT_OK:
        MOVE    teSelStart(A3),D0               | D0 = selStart
TEDELETE_CONT_CONT_3:
        MOVE    D0,D1                           | D1 = D0 (end of word)
        BEQ.B   TEFINDWORD_CONT                 | at start: scan forward
TEDELETE_CONT_CONT_4:
        SUBQ.W  #0x1,D0                         | step back one char
        BLS.B   TEFINDWORD_CONT                 | branch if <= (unsigned)
        MOVE    D0,A1                           | A1 = char offset
        BSR.B   TEFINDWORD_CONT_4               | test word break at A1
        BEQ.B   TEDELETE_CONT_CONT_4            | not break: keep stepping back
        ADDQ.W  #0x1,D0                         | move to first non-break char
TEFINDWORD_CONT:
        CMP     teLength(A3),D1                 | past end of text?
        BCC.B   TEFINDWORD_DONE                 | yes: done
        MOVE    D1,A1                           | A1 = char offset for word break test
        BSR.B   TEFINDWORD_CONT_4               | test word break at D1
        BNE.B   TEFINDWORD_DONE                 | is word break -> found end
        ADDQ.W  #0x1,D1                         | advance to next character
        BRA.B   TEFINDWORD_CONT                 | -> keep scanning forward
TEFINDWORD_DONE:
        RTS                                     | return to caller (@ $F98C)
| ----------------------------------------------------------
| TEFINDWORD_CONT_4
| Called during boot.
TEFINDWORD_CONT_4:
        MOVEM.L D0/A0-A1,-(SP)                  | save registers
        MOVE    A1,D0                           | D0 = char offset to test
        MOVE.L  teTextH(A3),A0                  | A0 = teTextH (text handle)
        MOVE.L  (A0),A0                         | A0 = dereferenced text ptr
        MOVE.L  teWordBreak(A3),A1              | A1 = teWordBreak proc ptr
        JSR     (A1)                            | call word break: Z=not break, NZ=break
        MOVEM.L (SP)+,D0/A0-A1                  | restore registers (CC preserved)
        RTS                                     | return result of word break callback
TEFINDWORD_CONT_4_CONT:
        CMPI.B  #0x20,0(A0,D0.W)                | char <= space (whitespace)?
        SLS     D0                              | D0 = $FF if word break
        TST.B   D0                              | set Z flag from D0
        RTS                                     | return Z=word, NZ=break
TEFINDWORD_CONT_4_NEXT:
        MOVEM.L D1-D7/A1-A2,-(SP)               | save working registers
        MOVE    6(A3),A2                        | A2 = destRect.right
        SUBA.W  2(A3),A2                        | A2 = destRect width
        SUBQ.W  #0x1,A2                         | leave 1 pixel margin
        MOVEQ.L #-0x2,D5                        | D5 = -2 (initial line start)
        MOVEQ.L #-0x1,D7                        | D7 = -1 (no last word break)
TEFINDWORD_CONT_4_CONT_2:
        MOVE    D6,D3                           | D3 = current scan offset
TEFINDWORD_CONT_4_CONT_3:
        CMP     teLength(A3),D3                 | past end of text?
        BCC.B   TEFINDWORD_CONT_4_CONT_6        | yes: end of last line
        TST.B   0x48(A3)                        | crOnly mode (no word wrap)?
        BNE.B   TEFINDWORD_CONT_4_NO            | yes: skip wrap logic
        TST     D7                              | any prior word break seen?
        BEQ.B   TEFINDWORD_CONT_4_CONT_4        | no: scan from D3
        MOVE    D3,D0                           | D0 = current offset
        BSR.B   TEDELETE_CONT_CONT_3            | find next word boundary -> D1
        BRA.B   TEFINDWORD_CONT_4_CONT_5        | measure that range
TEFINDWORD_CONT_4_CONT_4:
        MOVE    D3,D1                           | D1 = D3
        ADDQ.W  #0x1,D1                         | advance one char
TEFINDWORD_CONT_4_CONT_5:
        MOVE    D1,D3                           | D3 = candidate end of line
        BSR.W   TECLICK_CONT_5_CONT_7           | measure width D6..D3 -> D0
        CMP     A2,D0                           | fits within destRect width?
        BGE.B   TEFINDWORD_CONT_4_CONT_7        | no: wrap before this word
TEFINDWORD_CONT_4_NO:
        MOVE    D3,D5                           | store new lineStart; advance
        MOVE.L  teTextH(A3),A0                  | A0 = text handle (hText)
        MOVE.L  (A0),A0                         | A0 = text data ptr
        CMPI.B  #0xD,0(A0,D3.W)                 | CR at D3?
        BEQ.B   TEFINDWORD_CONT_4_CONT_7        | yes: hard line break
        ADDQ.W  #0x1,D3                         | advance scan offset
        BRA.B   TEFINDWORD_CONT_4_CONT_3        | continue scanning
TEFINDWORD_CONT_4_CONT_6:
        MOVE    teLength(A3),D5                 | D5 = end of last line
        SUBQ.W  #0x1,D5                         | step back to last char
TEFINDWORD_CONT_4_CONT_7:
        MOVEQ.L #0x0,D7                         | D7 = 0 (line wrapped)
        ADDQ.W  #0x1,D5                         | D5 = next line start offset
        BMI.B   TEFINDWORD_CONT_4_CONT_2        | overflow: continue scan
        MOVE    D5,D0                           | D0 = next line start (return)
        MOVEM.L (SP)+,D1-D7/A1-A2               | restore working registers
        RTS                                     | return next lineStart in D0
TEFINDWORD_CONT_4_CONT_8:
        MOVE.L  (TERecal).w,-(SP)               | push TERecal hook for jump
        RTS                                     | jump via TERecal hook
TEFINDWORD_CONT_4_CONT_9:
        LINK    A6,#0x0                         | set up local frame
        MOVEM.L D2-D6/A2,-(SP)                  | save working registers
        LEA.L     0x5E(A3),A2                   | A2 -> nLines field
        CLR     (A2)+                           | clear nLines = 0
        BSR.W   TEDELETE_CONT_OK                | find first wrap region start
        MOVE    D0,D3                           | D3 = first changed char
        BEQ.B   TEFINDWORD_CONT_4_CONT_11       | at start: empty preserved
        SUBQ.W  #0x1,D3                         | back up one char
TEFINDWORD_CONT_4_CONT_10:
        MOVE    (A2)+,D6                        | D6 = old lineStart, A2++
        MOVE    D6,-22(A6)                      | save D6 to local frame
        MOVE    (A2),D0                         | D0 = next old lineStart
        CMP     teLength(A3),D0                 | past end?
        BCC.B   TEFINDWORD_CONT_4_CONT_13       | yes: stop preserving
        CMP     D0,D3                           | line still before D3?
        BCS.B   TEFINDWORD_CONT_4_CONT_13       | no: must recalc this one
        ADDQ.W  #0x1,0x5E(A3)                   | count preserved line
        BRA.B   TEFINDWORD_CONT_4_CONT_10       | advance to next line
TEFINDWORD_CONT_4_CONT_11:
        MOVE    (A2)+,D6                        | D6 = old lineStart, A2++
        BRA.B   TEFINDWORD_CONT_4_CONT_13       | enter recalc loop
TEFINDWORD_CONT_4_CONT_12:
        CMP     teLength(A3),D6                 | past end of text?
        BCC.B   P_TERECAL_DONE_2                | yes -> done recalculating
TEFINDWORD_CONT_4_CONT_13:
        BSR.W   TEFINDWORD_CONT_4_NEXT          | find next line break -> D0
        MOVE    D0,D3                           | D3 = new line start
        CMP     teSelEnd(A3),D3                 | past teSelEnd?
        BLS.B   TEFINDWORD_CONT_4_NO_2          | no -> keep inserting new lines
        SUB     D3,(A2)                         | compute delta from old lineStart
        CMP     (A2),D7                         | delta matches insertion offset?
        BEQ.B   TEFINDWORD_CONT_4_OK            | yes -> remaining lines just need adjustment
TEFINDWORD_CONT_4_NO_2:
        BSR.B   P_TERECAL_NEXT_3                | grow handle if needed; bump nLines
        MOVE    D3,(A2)+                        | store new lineStart, A2++
        MOVE    D3,D6                           | D6 = new lineStart
        BRA.B   TEFINDWORD_CONT_4_CONT_12       | -> draw caret
TEFINDWORD_CONT_4_OK:
        MOVE    D3,-14(A6)                      | save new lineStart in frame
        ADD     D3,(A2)                         | (A2) += D3
P_TERECAL_NO_2:
        BSR.B   P_TERECAL_NEXT_3                | grow handle if needed; bump nLines
        SUB     D7,(A2)                         | adjust old lineStart by removed chars
        MOVE    (A2)+,D6                        | D6 = adjusted lineStart; advance
        CMP     teLength(A3),D6                 | past end of text?
        BCS.B   P_TERECAL_NO_2                  | no -> keep adjusting remaining lines
P_TERECAL_DONE_2:
        BSR.B   P_TERECAL_NEXT_3                | ensure space for sentinel entry
        MOVE    D6,-(A2)                        | store final lineStart (sentinel)
        SUBQ.W  #0x1,0x5E(A3)                   | adjust nLines (subtract extra count)
        TST     teLength(A3)                    | is text empty?
        BNE.B   P_TERECAL_DONE_3                | has text: keep nLines
        CLR     0x5E(A3)                        | empty text -> nLines = 0
P_TERECAL_DONE_3:
        MOVEM.L (SP)+,D2-D6/A2                  | restore registers
        UNLK    A6                              | tear down frame
        RTS                                     | return from sentinel entry insertion
P_TERECAL_NEXT_3:
        ADDQ.W  #0x1,0x5E(A3)                   | bump nLines counter
        MOVE.L  A4,A0                           | A0 = TE handle
        _GetHandleSize                          | D0 = current TE handle size
        MOVE.L  D0,D1                           | D1 = current size
        MOVEQ.L #teRecSize,D0                   | base TE record size
        ADD     0x5E(A3),D0                     | + nLines * 2 (lineStarts[])
        ADD     0x5E(A3),D0                     | ... twice because each lineStart is 2 bytes
        CMP.L   D0,D1                           | need to grow handle?
        BGE.B   P_TERECAL_DONE_4                | no: enough space already
        SUBA.L  A3,A2                           | A2 = offset into TERec
        ADDQ.W  #0x8,D0                         | add slack for future lines
        BCLR    #0x7,(A4)                       | unlock TE handle for resize
        _SetHandleSize                          | grow TE handle
        _HLock                                  | re-lock TE handle
        MOVE.L  (A4),A3                         | A3 = new TERec base
        ADDA.L  A3,A2                           | A2 = restored ptr in new base
P_TERECAL_DONE_4:
        RTS                                     | return from grow check

| P_TERECAL_NO_3 -- set caret state.
| ----------------------------------------------------------
| P_TERECAL_NO_3
| Called by: TESetSelect, TECLICK_NO_2, TECLICK_CONT_4, TEDelete, P_TERECAL_CONT_4_CONT (and 2 more)
P_TERECAL_NO_3:
        TST.B   teActive(A3)                    | is TE active?
        BEQ.B   P_TERECAL_DONE_4                | inactive: skip caret
        MOVE    teSelStart(A3),D0               | D0 = selStart
        CMP     teSelEnd(A3),D0                 | insertion point?
        BNE.B   P_TERECAL_DONE_4                | has selection: no caret
        LEA.L     teCarAct(A3),A0               | A0 = &0x39(A3)
        ST      (A0)                            | (A0) := -1 (true)
        TST.B   -(A0)                           | caret already shown?
        BNE.B   P_TERECAL_DONE_4                | yes: skip toggle
        ST      (A0)                            | (A0) := -1 (true)
P_TERECAL_OK_3:                                 | BRA.W reach-extender
        BRA.B   P_TERECAL_CONT_4                | draw caret (XOR)
| Called by: TESetSelect, TEClick, TECLICK_EMPTY, TEDelete, TEDeactivate (and 4 more)
P_TERECAL_CONT_3:
        TST.B   teActive(A3)                    | is TE active?
        BEQ.B   P_TERECAL_DONE_4                | inactive: nothing to erase
        LEA.L     teCarAct(A3),A0               | A0 = &0x39(A3)
        SF      (A0)                            | set false (=0): (A0)
        TST.B   -(A0)                           | was caret showing?
        BEQ.B   P_TERECAL_DONE_4                | no: nothing to erase
        SF      (A0)                            | set false (=0): (A0)

| P_TERECAL_CONT_4 -- draw/erase caret (XOR).
P_TERECAL_CONT_4:
        MOVEM.L D0-D7,-(SP)                     | save data registers
        MOVE    teSelStart(A3),D3               | D3 = selStart (caret pos)
        MOVE    D3,D4                           | D4 = D3 (zero-width range)
        MOVEQ.L #-0x2,D7                        | D7=-2: caret mode
        BSR.W   XTRIMMEASURE_OK_CONT_2          | compute caret rect on this line
        MOVE    0x32(A0),D0                     | D0 = pen.h (caret x)
        MOVE    D0,22(A3)                       | store caret rect right
        SUBQ.W  #0x1,D0                         | caret is 1 pixel wide
        MOVE    D0,18(A3)                       | store caret rect left
        MOVE.L  0x5A(A3),D0                     | D0 = teCaretHook
        BSR.W   XTRIMMEASURE_CONT_7             | invert caret rect
        MOVEM.L (SP)+,D0-D7                     | restore data registers
        RTS                                     | return from caret toggle

| ----------------------------------------------------------
| TEActivate -- _TEActivate ($A9D8).
| Activate a TERec: enable caret blink (if no selection),
| set teActive flag, redraw highlight.
TEActivate:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        TST.B   teActive(A3)                    | already active?
        BNE.B   TEACTIVATE_OK                   | yes -> nothing to do
        MOVE    teSelStart(A3),D0               | D0 = teSelStart
        CMP     teSelEnd(A3),D0                 | insertion point? (selStart == selEnd)
        BNE.B   TEACTIVATE_NO                   | no -> has selection
        ST      teCarAct(A3)                    | teCarAct = true (enable caret)
TEACTIVATE_NO:
        ST      teActive(A3)                    | teActive(A3) := -1 (true)
        BSR.W   TEUPDATE_CONT_2                 | redraw selection highlight
TEACTIVATE_OK:
        BRA.B   TEIDLE_EXIT                     | share TE common epilog

| ----------------------------------------------------------
| TEDeactivate -- _TEDeactivate ($A9D9).
| Deactivate a TERec: hide caret, unhighlight, clear teActive.
TEDeactivate:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        TST.B   teActive(A3)                    | already inactive?
        BEQ.B   TEIDLE_EXIT                     | already inactive: skip
        BSR.B   P_TERECAL_CONT_3                | hide caret
        BSR.W   TEUPDATE_CONT_2                 | unhighlight selection
        SF      teActive(A3)                    | clear teActive
        BRA.B   TEIDLE_EXIT                     | share TE common epilog

| ----------------------------------------------------------
| TEIdle -- _TEIdle ($A9DA).
| Blink the caret if its time has come.
TEIdle:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state (A3=TERec)
        TST.B   teCarAct(A3)                    | caret enabled?
        BEQ.B   TEIDLE_EXIT                     | caret disabled: nothing to do
        SUBQ.W  #0x4,SP                         | room for tick count result
        _TickCount                              | get current tick count
        MOVEA.L (SP)+,A0                        | A0 = current ticks
        CMPA.L  teCarTime(A3),A0                | time to blink yet?
        BCS.B   TEIDLE_EXIT                     | no -> wait
        ADDA.L  (CaretTime).w,A0                | schedule next blink
        MOVE.L  A0,teCarTime(A3)                | save next blink time
        BSR.W   P_TERECAL_CONT_4                | XOR caret
        NOT.B   teCarOn(A3)                     | flip caret-on flag
TEIDLE_EXIT:
        BRA.W   TECALTEXT_EXIT                  | share TE common epilog

| ----------------------------------------------------------
| TEPaste -- _TEPaste ($A9DB).
| Insert TEScrap at the selection.
TEPaste:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        MOVE.L  (TEScrpHandle).w,A1             | A1 = scrap handle
        BSET    #0x7,(A1)                       | lock scrap handle
        MOVE.L  (A1),D6                         | D6 = dereferenced scrap text ptr
        MOVEQ.L #0x0,D5                         | clear high word
        MOVE    (TEScrpLength).w,D5             | D5 = scrap length
        BSR.B   P_TERECAL_CONT_4_CONT           | insert scrap text, replacing selection
        MOVE.L  (TEScrpHandle).w,A1             | A1 = scrap handle
        BCLR    #0x7,(A1)                       | unlock scrap handle
        BRA.B   TEIDLE_EXIT                     | -> TE exit
P_TERECAL_CONT_4_CONT:
        BSR.W   P_TERECAL_CONT_3                | hide caret if visible
        BSR.W   TEUPDATE_CONT_2                 | unhighlight current selection
        BSR.W   TEDELETE_CONT                   | delete selected text
        BSR.B   P_TERECAL_CONT_4_CONT_2         | insert D6[D5] at selStart
        BSR.W   TEDELETE_CONT_CONT_2            | recalc lines + erase area
        LEA.L     teSelStart(A3),A0             | A0 = &0x20(A3)
        ADD     D5,(A0)                         | (A0) += D5
        MOVE    (A0)+,(A0)                      | selEnd = selStart (collapse)
        BSR.W   P_TERECAL_NO_3                  | set caret state
        RTS                                     | return from paste/insert
P_TERECAL_CONT_4_CONT_2:
        SUBQ.L  #0x4,SP                         | space for Munger result
        MOVE.L  teTextH(A3),A0                  | A0 = text handle (hText)
        MOVE.L  A0,-(SP)                        | push handle for HUnlock
        _HUnlock                                | unlock text before Munger
        MOVE    teSelStart(A3),-(SP)            | push offset = selStart
        CLR     -(SP)                           | zero-extend offset
        CLR.L   -(SP)                           | ptr1 = nil (no search)
        CLR.L   -(SP)                           | len1 = 0 (insert only)
        MOVE.L  D6,-(SP)                        | push insert ptr (D6)
        MOVE.L  D5,-(SP)                        | push len2 = D5 (bytes to insert)
        _Munger                                 | insert D5 bytes at selStart
        ADDQ.L  #0x4,SP                         | discard Munger result
        MOVE.L  teTextH(A3),A0                  | A0 = text handle
        _HLock                                  | re-lock text handle
        ADD     D5,teLength(A3)                 | teLength(A3) += D5
        SUB     D5,D7                           | D7 -= D5 (delete delta)
        RTS                                     | return from text insert

| ----------------------------------------------------------
| TEInsert -- _TEInsert ($A9DE).
| Insert text at the current selection point. If selection is
| not empty, the selected text is deleted first.
TEInsert:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state (12 bytes params)
        BSR.W   P_TERECAL_CONT_3                | hide caret
        BSR.W   TEUPDATE_CONT_2                 | unhighlight selection
        MOVEQ.L #0x0,D7                         | D7 = 0 (no chars deleted)
        MOVEM.L (A2)+,D5-D6                     | D5=text length, D6=text ptr (params)
        BSR.B   P_TERECAL_CONT_4_CONT_2         | _Munger to insert
        BSR.W   TEDELETE_CONT_CONT_2            | recalculate lines and redraw
        ADD     D5,teSelStart(A3)               | teSelStart += inserted length
        ADD     D5,teSelEnd(A3)                 | teSelEnd += inserted length
        BSR.W   P_TERECAL_NO_3                  | set caret state
        BSR.W   TEUPDATE_CONT_2                 | highlight selection
TEINSERT_EXIT:
        MOVEQ    #0xC,D0                        | strip 12 param bytes
        BRA.W    TECALTEXT_EXIT_2               | share TE epilog

| ----------------------------------------------------------
| TEKey -- _TEKey ($A9DC).
| Process a typed character: backspace deletes the char before
| the cursor; otherwise the char is inserted at the selection.
TEKey:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state (A3=TERec, A2=params)
        ST      0x47(A3)                        | teLftCaret (+$47) := TRUE
        _ObscureCursor                          | hide cursor during typing
        MOVE    (A2),D1                         | D1 = key character
        CMPI.B  #0x8,D1                         | backspace?
        BEQ.B   TEKEY_OK                        | yes, handle delete ->
        MOVE.L  A2,D6                           | D6 = ptr to character to insert
        ADDQ.W  #0x1,D6                         | point past key word to char byte
        MOVEQ.L #0x1,D5                         | D5 = 1 character to insert
        BSR.W   P_TERECAL_CONT_4_CONT           | TEInsert: replace selection with char
        BRA.B   TEKEY_DONE                      | -> done

| backspace: delete character before selection
TEKEY_OK:
        MOVE    teSelStart(A3),D0               | D0 = selStart
        CMP     teSelEnd(A3),D0                 | selStart == selEnd? (no selection)
        BNE.B   TEKEY_CONT                      | has selection, delete it ->
        TST     D0                              | at beginning of text?
        BEQ.B   TEKEY_DONE                      | yes -> nothing to delete
        BSR.W   P_TERECAL_CONT_3                | hide caret
        SUBQ.W  #0x1,teSelStart(A3)             | selStart-- (select char before cursor)
TEKEY_CONT:
        MOVE.L  A4,-(SP)                        | push TE handle for TEDelete
        _TEDelete                               | delete selected/back char
TEKEY_DONE:
        MOVEQ.L #0x6,D0                         | strip 6 param bytes
        BRA.W   TECALTEXT_EXIT_2                | share TE epilog

| ----------------------------------------------------------
| TEScroll -- _TEScroll ($A9DD).
| Scroll text within view rect by (dh, dv) offsets via _ScrollRect.
| Redraws caret and uses temp clip rgn for affected area.
TEScroll:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        BSR.W   P_TERECAL_CONT_3                | hide caret
        MOVE.L  (A2)+,D2                        | D2 = (dh, dv) offsets from param
        PEA.L     (A3)                          | push destRect
        MOVE.L  D2,-(SP)                        | push offsets
        _OffsetRect                             | offset destRect by (dh, dv)
        SUBQ.W  #0x4,SP                         | make room for NewRgn result
        _NewRgn                                 | A0 = new empty region
        MOVE.L  (SP)+,A2                        | A2 = new rgn
        PEA.L     8(A3)                         | push viewRect
        MOVE.L  D2,-(SP)                        | push offsets
        MOVE.L  A2,-(SP)                        | push update rgn
        _ScrollRect                             | scroll viewRect, accumulate update rgn
        BSR.W   P_TERECAL_NO_3                  | redraw caret
        MOVE.L  A2,-(SP)                        | push update rgn
        _SetClip                                | clip drawing to update area
        MOVE.L  (A2),A0                         | A0 = update rgn dereferenced
        MOVE    2(A0),D0                        | D0 = top of rgn bounds
        MOVE    6(A0),D1                        | D1 = bottom of rgn bounds
        BSR.B   XTRIMMEASURE_CONT_6_CONT        | redraw text in update range
        MOVE.L  A2,-(SP)                        | push update rgn
        _DisposeRgn                             | release temp rgn
TESCROLL_EXIT:
        MOVEQ.L #0x8,D0                         | D0 = frame size to discard
        BRA.W   TECALTEXT_EXIT_2                | -> UNLK + return

| ----------------------------------------------------------
| TESetJust -- _TESetJust ($A9DF) (also called _TextStyle).
| Set the justification field (teJust): -1=right, 0=left, 1=center.
TESetJust:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        MOVE    (A2),teJust(A3)                 | store new justification
        BRA.B   TEKEY_DONE                      | -> common TE epilog

| ----------------------------------------------------------
| XTRIMMEASURE_CONT_6
| Called during boot.
XTRIMMEASURE_CONT_6:
        SUB     (A3),D0                         | D0 = pixel y - destRect.top
        EXT.L    D0                             | sign-extend D0 to long
        DIVS    24(A3),D0                       | D0 = D0 /s 24(A3)
        CMP     0x5E(A3),D0                     | compare with total lines (sets CC)
XTRIMMEASURE_CONT_6_RTS:                        | shared early-exit target
        RTS                                     | caller checks GE for past-end
XTRIMMEASURE_CONT_6_CONT:
        MOVEQ.L #0x0,D3                         | D3 = 0 (range start char)
        BSR.B   XTRIMMEASURE_CONT_6             | y -> line number
        BGE.B   XTRIMMEASURE_CONT_6_CONT_2      | past end: skip table lookup
        ADD     D0,D0                           | line *= 2 (word offset)
        BLT.B   XTRIM_CBMLOAD_NEG1              | negative: skip indexed load
        MOVE    0x60(A3,D0.W),D3                | D3 = lineStarts[line] (teLines +$60)
XTRIM_CBMLOAD_NEG1:
        MOVEQ.L #-0x1,D4                        | D4 = -1 (default end)
        ADD     teLineHite(A3),D1               | D1 = bottom + lineHeight
        SUBQ.W  #0x1,D1                         | step back to last visible row
        MOVE    D1,D0                           | D0 = bottom y
        BSR.B   XTRIMMEASURE_CONT_6             | y -> end line number
        BGE.B   XTRIM_CBMLOAD_LAST_D7NEG1       | past end -> D4=-1, skip table
        ADD     D0,D0                           | line *= 2 (word offset)
        MOVE    0x60(A3,D0.W),D4                | D4 = lineStarts[line] (teLines +$60)
XTRIM_CBMLOAD_LAST_D7NEG1:
        MOVEQ.L #-0x1,D7                        | D7=-1: draw mode
        BSR.W   XTRIMMEASURE_OK_CONT_2          | draw lines D3..D4
XTRIMMEASURE_CONT_6_CONT_2:
        BSR.W   TEUPDATE_CONT_2                 | redraw selection hilite
        TST.B   teCarOn(A3)                     | caret currently visible?
        BEQ.B   XTRIMMEASURE_CONT_6_RTS         | zero -> early RTS
        BRA.W   P_TERECAL_OK_3                  | -> P_TERECAL_CONT_4 via .W reach extender
