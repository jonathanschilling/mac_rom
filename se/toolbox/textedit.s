| TextEdit
|
| Apple source: TextEdit.a (MacSEROM.lst module TEXTEDIT). Basic text
| editing: TEGetText, TEInit, TEDispose, TextBox, TESetText, TECalText,
| TESetSelect, TENew, TEUpdate, TEClick, TECopy, TECut, TEDelete,
| TEActivate, TEDeactivate, TEIdle, TEPaste, TEInsert, TEKey, TESetJust,
| TEScroll, TEPinScroll, TESelView, TEAutoView (automatic scrolling), and the
| SE addition TEGetOffset ($A83C), with the internal
| measuring/line-breaking routines (XTrimMeasure, TEFindWord, TEFindLine,
| vectored through the low-memory TE hooks).
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
| Offset 66: recalBack INTEGER TEFlags; bit 6 = auto-view (TEAutoView)
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

TEXTEDIT:
    .long       0x14E41B28
    .long       0x1E181CD2
    .long       0x1E841E96
| ----------------------------------------------------------
|
| _TEGetText ($A9CB) -- return TERec.hText handle
|
| Stack: hTE(L) -> Handle. Walks the TERec to find hText
| (the Pascal handle to the underlying text storage) and
| returns it on the stack.
|
TEGETTEXT:
    BSR.W       TE_PROLOGUE_NODISP              | A3 = TERec, A2 = result slot
    MOVE.L      0x3E(A3),(A2)                   | result := TERec.hText (offset 0x3E)
    BRA.W       TECALTEXT_EXIT                  | -> common exit (strip params)
| ----------------------------------------------------------
| _TEInit ($A9CC) - initialize TextEdit globals.
| Allocates empty scrap handle and installs default
| TEDoText/TERecal/TEWdBreak hook procedures.
| ----------------------------------------------------------
TEINIT:
    MOVEQ.L     #0x0,D0                         | D0 = 0 (empty scrap)
    MOVE.W      D0,(TEScrpLength).W             | TEScrpLength = 0 (no scrap text yet)
    _NewHandle                                  | allocate empty handle
    MOVE.L      A0,(TEScrpHandle).W             | TEScrpHandle = empty handle
    LEA.L       P_TEDoText(PC),A0               | default text drawing/measuring
    MOVE.L      A0,(TEDoText).W                 | install TEDoText hook
    LEA.L       P_TERecal(PC),A0                | default line recalculation
    MOVE.L      A0,(TERecal).W                  | install TERecal hook
    LEA.L       P_TEWdBreak(PC),A0              | default word break detection
    MOVE.L      A0,(TEWdBreak).W                | install TEWdBreak hook
    RTS                                         | return from default hook installation
| ----------------------------------------------------------
| _TEDispose ($A9CD) - free TERec and its text handle.
| If teStyleRec (high bit of teJust+1) is set, also frees
| the StyleRec, its element handle, and line height handle.
| (SE FDHD adds StyleRec disposal that Plus's TEDispose lacks.)
| ----------------------------------------------------------
TEDISPOSE:
    LINK        A6,#0x0                         | set up stack frame
    MOVEM.L     D2-D7/A2-A4,-(A7)               | save registers
    MOVEA.L     0x8(A6),A4                      | A4 = TEHandle (param)
    MOVEA.L     (A4),A3                         | A3 = dereferenced TERec
    MOVEA.L     0x3E(A3),A0                     | A0 = text handle (teTextH)
    _DisposeHandle                              | free the text buffer
    TST.W       0x50(A3)                        | teStyleRec flag set?
    BPL.B       TEDISPOSE_FREE_STYLEREC         | no styled TE: skip style cleanup
    MOVEA.L     0x4A(A3),A2                     | A2 = StyleRec handle
    MOVEA.L     (A2),A2                         | A2 = dereferenced StyleRec
    MOVEA.L     0x4(A2),A0                      | A0 = element handle
    _DisposeHandle                              | free element handle
    MOVEA.L     0x8(A2),A0                      | A0 = line heights handle
    _DisposeHandle                              | free line heights handle
    MOVEA.L     0x4A(A3),A0                     | A0 = StyleRec handle
    _DisposeHandle                              | free the StyleRec itself
TEDISPOSE_FREE_STYLEREC:
    MOVEA.L     A4,A0                           | A0 = TEHandle
    _DisposeHandle                              | free the TERec itself
    MOVEQ.L     #0x4,D0                         | param size = 4 (TEHandle)
    BRA.W       TE_EXIT_TAIL                    | -> shared TE epilogue
| ----------------------------------------------------------
| _TETextBox ($A9CE) - draw text in a box with justification.
| Single-line fast path uses _TextWidth/_DrawText with optional
| centering or right-justify. Multi-line path (CR found or text
| wider than box) uses temporary _TENew + _TESetText + _TEUpdate.
| ----------------------------------------------------------
TEXTBOX:
    LINK        A6,#0x0                         | set up stack frame
    MOVEM.L     D2-D7/A2-A4,-(A7)               | save registers
    MOVEA.L     0x12(A6),A0                     | A0 = text pointer (param)
    MOVE.L      0xE(A6),D0                      | D0 = text length (param)
    BLT.W       TETEXTBOX_NO                    | negative length -> bail
    BEQ.B       TETEXTBOX_EMPTY                 | empty text -> try single-line path
TETEXTBOX_CONT:
    CMPI.B      #0xD,(A0)+                      | scan for carriage return
    BEQ.B       TETEXTBOX_FOUND                 | found CR -> use multi-line TENew path
    SUBQ.L      #0x1,D0                         | decrement scan counter
    BNE.B       TETEXTBOX_CONT                  | more chars -> keep scanning
TETEXTBOX_EMPTY:
    SUBQ.W      #0x2,A7                         | space for TextWidth result
    MOVE.L      0x12(A6),-(A7)                  | push text pointer
    CLR.W       -(A7)                           | firstByte = 0
    MOVE.W      0x10(A6),-(A7)                  | push byte count
    _TextWidth                                  | measure text width
    MOVE.W      (A7)+,D3                        | D3 = text width in pixels
    MOVEA.L     0xA(A6),A0                      | A0 = box rect pointer (param)
    MOVE.W      0x6(A0),D0                      | D0 = rect.right
    SUB.W       0x2(A0),D0                      | D0 = box width
    SUBQ.W      #0x2,D0                         | subtract 2 pixel margin
    CMP.W       D3,D0                           | text fits in one line?
    BLE.B       TETEXTBOX_FOUND                 | no -> use multi-line path
    MOVE.L      A0,-(A7)                        | push box rect
    _EraseRect                                  | clear the box
    SUBQ.W      #0x8,A7                         | space for FontInfo (4 words)
    MOVE.L      A7,-(A7)                        | push FontInfo ptr
    _GetFontInfo                                | get current font metrics
    MOVE.W      (A7)+,D0                        | D0 = ascent
    ADDQ.W      #0x6,A7                         | skip descent, widMax, leading
    MOVEA.L     0xA(A6),A0                      | A0 = box rect
    MOVE.L      (A0),-(A7)                      | push rect.top,left as pen position
    ADD.W       D0,(A7)                         | add ascent to top for baseline
    ADDQ.W      #0x1,0x2(A7)                    | indent 1 pixel from left edge
    _MoveTo                                     | position pen at first baseline
    TST.W       0x8(A6)                         | justification param (0=left)
    BEQ.B       TETEXTBOX_CONT_3                | left-justified -> draw directly
    MOVEA.L     0xA(A6),A0                      | A0 = box rect
    MOVE.W      0x6(A0),D0                      | D0 = rect.right
    SUB.W       0x2(A0),D0                      | D0 = box width
    SUB.W       D3,D0                           | D0 = extra space after text
    SUBQ.W      #0x1,D0                         | account for margin
    TST.W       0x8(A6)                         | check justification sign
    BMI.B       TETEXTBOX_CONT_2                | negative (-1) = right-justify
    ASR.W       #0x1,D0                         | center: divide slack by 2
TETEXTBOX_CONT_2:
    MOVE.W      D0,-(A7)                        | push horizontal offset
    CLR.W       -(A7)                           | vertical offset = 0
    _Move                                       | adjust pen position
TETEXTBOX_CONT_3:
    MOVE.L      0x12(A6),-(A7)                  | push text pointer
    CLR.W       -(A7)                           | firstByte = 0
    MOVE.W      0x10(A6),-(A7)                  | push byte count
    _DrawText                                   | draw the text
TETEXTBOX_NO:
    BRA.B       TETEXTBOX_DISPOSE_TAIL          | -> clean up and return
| ----------------------------------------------------------
|
| TETEXTBOX_FOUND - multi-line path: use temporary TERec.
| Creates TERec with destRect = viewRect = box, sets justification,
| installs text via TESetText, draws via TEUpdate, then disposes.
|
| Called during boot.
TETEXTBOX_FOUND:
    SUBQ.W      #0x4,A7                         | space for TENew result
    MOVE.L      0xA(A6),-(A7)                   | push destRect = box rect
    MOVE.L      (A7),-(A7)                      | push viewRect = same box rect
    MOVE.L      (A7),-(A7)                      | dup for EraseRect
    _EraseRect                                  | clear the box area
    _TENew                                      | create temporary TERec
    MOVEA.L     (A7)+,A4                        | A4 = TEHandle
    MOVEA.L     (A4),A0                         | A0 = dereferenced TERec
    MOVE.W      0x8(A6),0x3A(A0)                | set teJust from param
    MOVE.L      0xE(A6),D0                      | D0 = text length
    BEQ.B       TETEXTBOX_SKIP                  | empty -> skip text setup
    MOVE.L      0x12(A6),-(A7)                  | push text pointer
    MOVE.L      D0,-(A7)                        | push text length
    MOVE.L      A4,-(A7)                        | push TEHandle
    _TESetText                                  | set the text content
    MOVE.L      0xA(A6),-(A7)                   | push update rect = box rect
    MOVE.L      A4,-(A7)                        | push TEHandle
    _TEUpdate                                   | draw all text lines
TETEXTBOX_SKIP:
    MOVE.L      A4,-(A7)                        | push TEHandle
    _TEDispose                                  | dispose temporary TERec
TETEXTBOX_DISPOSE_TAIL:
    MOVEQ.L     #0xE,D0                         | param size = 14 bytes
    BRA.W       TE_EXIT_TAIL                    | -> TE epilogue with cleanup
| ----------------------------------------------------------
| _TESetText ($A9CF) - replace all text in a TextEdit field.
| Pascal: procedure TESetText(text: Ptr; length: LongInt; hTE: TEHandle);
| ----------------------------------------------------------
TESETTEXT:
    BSR.W       TE_PROLOGUE_NODISP              | set up TE state (A3=TERec, A2=params)
    MOVE.L      (A2)+,D0                        | D0 = text length
    MOVE.W      D0,0x20(A3)                     | selStart = length (cursor at end)
    MOVE.W      D0,0x22(A3)                     | selEnd = length
    MOVE.W      D0,0x3C(A3)                     | teLength = new length
    MOVEA.L     0x3E(A3),A0                     | A0 = text handle (teTextH)
    MOVE.L      D0,-(A7)                        | save length on stack
    _HUnlock                                    | unlock text handle before resize
    MOVE.L      (A7)+,D0                        | restore length
    MOVEA.L     (A2)+,A0                        | A0 = text pointer
    MOVEA.L     0x3E(A3),A1                     | A1 = text handle
    _PtrToXHand                                 | copy text into handle (resizes)
    MOVEA.L     0x3E(A3),A0                     | A0 = text handle
    _HLock                                      | re-lock text for drawing
    BSR.W       TE_RESIZE_STYLERECS             | resize style structures (if styled TE)
    BSR.W       TESETTEXT_CONT                  | recalculate line starts and redraw
TESETTEXT_EXIT:
    BRA.W       TE_INSERT_EPILOGUE              | -> TE exit
| ----------------------------------------------------------
| TE_RESIZE_STYLERECS - resize StyleRec arrays after text change.
| Only called for styled TextEdit (high bit of $50(A3) set).
| Resizes element handle to $1C bytes and line heights handle
| to $12 bytes, then re-initializes them with one-element
| placeholder runs covering the new text length.
| ----------------------------------------------------------
TE_RESIZE_STYLERECS:
    TST.W       0x50(A3)                        | teStyleRec flag set?
    BPL.B       TE_RESIZE_STYLERECS_RTS         | no styled TE: nothing to do
    MOVEA.L     0x4A(A3),A0                     | A0 = StyleRec handle
    MOVEQ.L     #0x1C,D0                        | resize to 28 bytes
    BSR.W       TE_RESIZE_TEXTHANDLE            | resize handle (re-locks text)
    MOVEA.L     (A0),A0                         | dereference StyleRec
    MOVEA.L     0x4(A0),A0                      | A0 = element handle
    MOVEQ.L     #0x12,D0                        | resize to 18 bytes
    BSR.W       TE_RESIZE_TEXTHANDLE            | resize element handle
    MOVEA.L     0x4A(A3),A0                     | A0 = StyleRec handle
    MOVEA.L     (A0),A0                         | dereference StyleRec
    MOVE.W      0x3C(A3),D0                     | D0 = teLength (new text length)
    BSR.W       TE_INIT_STYLEREC                | initialize style runs for new length
TE_RESIZE_STYLERECS_RTS:
    RTS                                         | return from style resize
| ----------------------------------------------------------
| TE_RESIZE_TEXTHANDLE - resize handle while keeping text handle locked.
| Unlocks text handle, resizes A0 to D0 bytes, re-locks text.
| Called by: TE_RESIZE_STYLERECS, TE_FULL_REBUILD_GROW_BUF, TE_REBUILD_LINEHEIGHTS, TE_GROW_STYLERUN_ARRAY, TE_APPEND_STYLEENTRY_LOOP
| ----------------------------------------------------------
TE_RESIZE_TEXTHANDLE:
    MOVEM.L     D0/A0,-(A7)                     | save D0 (size) and A0 (target handle)
    MOVEA.L     0x3E(A3),A0                     | A0 = text handle
    _HUnlock                                    | unlock text handle before resize
    MOVEM.L     (A7)+,D0/A0                     | restore size and target handle
    _SetHandleSize                              | resize the handle
    BNE.B       TE_RESIZE_SYSERROR              | error -> system error
    MOVEM.L     D0/A0,-(A7)                     | save again across HLock
    MOVEA.L     0x3E(A3),A0                     | A0 = text handle
    _HLock                                      | re-lock text after resize
    MOVEM.L     (A7)+,D0/A0                     | restore size and target handle
    RTS                                         | return from handle resize
| Called by: TENEW, TESTYLNEW, TE_RESIZE_TEXTHANDLE, TE_RESIZE_AND_DEREF
TE_RESIZE_SYSERROR:
    _SysError                                   | resize failed: fatal error
| ----------------------------------------------------------
| TE_INIT_STYLEREC - initialize StyleRec arrays with single style run.
| Entry: A0 = StyleRec base, D0 = text length.
| Sets nRuns=1, lineHeightTab.startChar=0, ends at -1 (sentinel),
| then calls TE_GET_FONT_INFO to fetch font ascent/lineHeight from
| current GrafPort and stores into the style record.
| ----------------------------------------------------------
TE_INIT_STYLEREC:
    MOVE.W      #0x1,(A0)                       | nStyles = 1
    MOVE.W      #0x1,0x2(A0)                    | nRuns = 1
    LEA.L       0x14(A0),A1                     | A1 -> first run entry
    CLR.L       (A1)+                           | run startChar = 0
    MOVE.W      D0,(A1)+                        | run lineHeight = text length
    MOVE.W      #0xFFFF,(A1)                    | sentinel: end-of-runs marker
    MOVEA.L     0x4(A0),A0                      | A0 = element handle
    MOVEA.L     (A0),A0                         | dereference to elements
    MOVE.W      #0x1,(A0)                       | first element index
    BSR.W       TE_GET_FONT_INFO                | fetch font ascent/leading -> D0/D1
    MOVE.W      D0,0x4(A0)                      | element.fontAscent
    MOVE.W      D1,0x2(A0)                      | element.lineHeight
    MOVEA.L     0x52(A3),A1                     | A1 = inPort (GrafPort)
    MOVE.W      0x44(A1),0x6(A0)                | element.txFont = port.txFont
    MOVE.W      0x46(A1),0x8(A0)                | element.txFace = port.txFace
    MOVE.W      0x4A(A1),0xA(A0)                | element.txSize = port.txSize
    PEA.L       0xC(A0)                         | push element.txColor ptr
    BSR.W       BuildHilitePattern              | copy port.fgColor into element.txColor
    RTS                                         | return from style init
| Called by: TE_INIT_STYLEREC, TENEW, TE_REBUILD_LINEHEIGHTS, PrimeStyleEntry, TEContinuousStyle_PlainPath
| ----------------------------------------------------------
| TE_GET_FONT_INFO - get current font ascent and lineHeight.
| Returns D0 = font ascent, D1 = ascent + descent + leading
| (full lineHeight). Preserves A0.
| ----------------------------------------------------------
TE_GET_FONT_INFO:
    MOVE.L      A0,-(A7)                        | save A0
    SUBQ.W      #0x8,A7                         | space for FontInfo (4 words)
    MOVE.L      A7,-(A7)                        | push FontInfo ptr
    _GetFontInfo                                | get current font metrics
    MOVE.W      (A7)+,D0                        | D0 = ascent
    MOVE.W      D0,D1                           | D1 = ascent (start of total)
    ADD.W       (A7)+,D1                        | D1 += descent
    ADDQ.W      #0x2,A7                         | skip widMax word
    ADD.W       (A7)+,D1                        | D1 += leading
    MOVEA.L     (A7)+,A0                        | restore A0
    RTS                                         | return D0 = ascent, D1 = lineHeight
| ----------------------------------------------------------
| TESETTEXT_CONT: recalculate all line starts after text change.
| Clears selStart, sets D7=$8002 (full recalc flag), calls
| P_doTERecal to rebuild line breaks and redraw, then restores
| selStart from the saved value.
| ----------------------------------------------------------
TESETTEXT_CONT:
    MOVE.L      0x20(A3),-(A7)                  | save selStart/selEnd
    CLR.W       0x20(A3)                        | clear selStart (for full recalc)
    MOVE.W      #0x8002,D7                      | flag: full recalculation needed
    CLR.L       0x60(A3)                        | clear line cache (recalLines)
    BSR.W       P_doTERecal                     | recalculate all line breaks
    MOVE.L      (A7)+,0x20(A3)                  | restore selStart/selEnd
    RTS                                         | return from full recalculation
| ----------------------------------------------------------
| _TECalText ($A9D0) - recalculate line starts after manual edit.
| ----------------------------------------------------------
TECALTEXT:
    BSR.W       TE_PROLOGUE_NODISP              | set up TE state
    BSR.B       TESETTEXT_CONT                  | recalculate all line starts
TECALTEXT_EXIT:
    MOVEQ.L     #0x4,D0                         | param size = 4 (TEHandle only)
TE_EXIT_4PARAM:
    MOVEA.L     0x8(A6),A4                      | A4 = TEHandle (re-read after calls)
    BRA.B       TE_EXIT_BODY                    | -> shared epilogue body
| Called by: TESTYLPASTE_ENTRY, TESetStyle_Exit, TEContinuousStyle_Exit, TEReplaceStyle_Exit, TEGetStyleHandle_Exit (and 1 more)
TE_EXIT_3PARAM:
    MOVEA.L     0xA(A6),A4                      | A4 = TEHandle (3-param variants)
TE_EXIT_BODY:
    MOVEA.L     (A4),A3                         | A3 = dereferenced TERec
    MOVE.W      D0,D4                           | D4 = saved param size
    MOVEA.L     0x3E(A3),A0                     | A0 = text handle
    MOVE.B      -0xC(A6),D0                     | D0 = saved text-handle state
    _HSetState                                  | restore text handle lock state
    MOVE.L      -0xA(A6),-(A7)                  | push saved clip region handle
    MOVE.L      (A7),-(A7)                      | dup for DisposeRgn
    _SetClip                                    | restore original clip region
    _DisposeRgn                                 | free temp clip region
    MOVEA.L     A4,A0                           | A0 = TEHandle
    MOVE.B      -0x2(A6),D0                     | D0 = saved TEHandle state
    _HSetState                                  | restore TEHandle lock state
    PEA.L       -0x18(A6)                       | push saved port info ptr
    BSR.W       PackTexturePattern              | restore port txFont/txFace/txSize
    MOVEA.L     0x52(A3),A0                     | A0 = inPort (GrafPort)
    MOVE.W      -0x12(A6),0x4A(A0)              | port.txSize = saved
    MOVE.W      -0x10(A6),0x46(A0)              | port.txFace = saved
    MOVE.W      -0xE(A6),0x44(A0)               | port.txFont = saved
    MOVE.L      -0x6(A6),-(A7)                  | push saved port
    _SetPort                                    | restore original port
    MOVE.W      D4,D0                           | D0 = param size for cleanup
TE_EXIT_TAIL:
    MOVEM.L     (A7)+,D2-D7/A2-A4               | restore registers
    UNLK        A6                              | tear down frame
    MOVEA.L     (A7)+,A0                        | A0 = return address
    ADDA.W      D0,A7                           | pop parameters
    JMP         (A0)                            | tail-call return from TE_EXIT_TAIL via A0
| ----------------------------------------------------------
| _TESetSelect ($A9D1) - change selection range.
| Pascal: procedure TESetSelect(selStart, selEnd: LongInt; hTE: TEHandle);
| Hides the caret/old selection, updates selStart/selEnd, then
| highlights the new selection and auto-scrolls into view.
| ----------------------------------------------------------
TESETSELECT:
    BSR.W       TE_PROLOGUE_NODISP              | set up TE state (12 bytes params)
    BSR.W       TE_CARET_ERASE                  | hide caret if visible
    BSR.W       TEUPDATE_CONT_2                 | unhighlight old selection
    MOVE.W      0xE(A6),0x22(A3)                | teSelEnd = new selEnd param
    MOVE.W      0x12(A6),0x20(A3)               | teSelStart = new selStart param
    BSR.W       XTRIMMEASURE_CONT_14            | clamp selection to text length
    BSR.W       TE_CARET_RESTORE                | set up caret state if no selection
    BSR.W       TEUPDATE_CONT_2                 | highlight new selection
    BSR.W       SelView                         | auto-scroll selection into view
    BRA.W       TESETTEXT_EXIT                  | -> TE exit
| ----------------------------------------------------------
| _TENew ($A9D2) - allocate a new TextEdit record.
| Pascal: function TENew(destRect, viewRect: Rect): TEHandle;
| Allocates 104-byte TERec, sets text handle, font metrics
| (ascent + lineHeight), grafPort, font/face/mode/size from
| current port, default word-break and click-loop hooks.
| (SE FDHD uses _HLock/_HUnlock vs Plus's BSET/BCLR #7,(A4).)
| ----------------------------------------------------------
TENEW:
    LINK        A6,#0x0                         | no local vars
    MOVEM.L     D2-D7/A2-A4,-(A7)               | save registers
    CLR.L       0x10(A6)                        | clear return value (TEHandle)
    MOVEQ.L     #0x68,D0                        | 104 bytes = sizeof(TERec)
    _NewHandleClear                             | allocate zeroed TERec
    BNE.W       TE_RESIZE_SYSERROR              | failed -> SysError
    MOVEA.L     A0,A4                           | A4 = TEHandle
    _HLock                                      | lock TEHandle (Memory Manager)
    MOVEA.L     (A4),A3                         | A3 = dereferenced TERec
    MOVEQ.L     #0x0,D0                         | zero-length handle
    _NewHandle                                  | empty text buffer
    BNE.W       TE_RESIZE_SYSERROR              | failed -> SysError
    MOVE.L      A0,0x3E(A3)                     | TERec.hText = empty text handle
    LEA.L       (A3),A0                         | A0 = TERec (destRect at offset 0)
    MOVEA.L     0xC(A6),A2                      | A2 = destRect parameter
    MOVE.L      (A2)+,(A0)+                     | copy destRect.topLeft
    MOVE.L      (A2)+,(A0)+                     | copy destRect.botRight
    MOVEA.L     0x8(A6),A2                      | A2 = viewRect parameter
    MOVE.L      (A2)+,(A0)+                     | copy viewRect.topLeft
    MOVE.L      (A2)+,(A0)+                     | copy viewRect.botRight
    BSR.W       TE_GET_FONT_INFO                | get font ascent + lineHeight
    MOVE.W      D0,0x1A(A3)                     | teAscent = ascent
    MOVE.W      D1,0x18(A3)                     | teLineHite = ascent+descent+leading
    MOVEA.L     (A5),A2                         | A2 = app globals handle
    MOVEA.L     (A2),A2                         | A2 = current GrafPort
    MOVE.L      A2,0x52(A3)                     | teGrafPort = current port
    MOVE.L      0x44(A2),0x4A(A3)               | copy port txFont+txFace to TERec
    MOVE.L      0x48(A2),0x4E(A3)               | copy port txMode+txSize to TERec
    MOVE.L      (TEWdBreak).W,0x26(A3)          | install default word-break proc
    LEA.L       DefClikProc(PC),A0              | A0 = default click-loop proc
    MOVE.L      A0,0x2A(A3)                     | teClikProc = default
    MOVEA.L     A4,A0                           | A0 = TEHandle
    _HUnlock                                    | unlock TEHandle
    MOVE.L      A4,0x10(A6)                     | store TEHandle as return value
    MOVEQ.L     #0x8,D0                         | param size = 8 (two rect ptrs)
    BRA.W       TE_EXIT_TAIL                    | -> TE exit
| ----------------------------------------------------------
| TEStylNew - allocate a styled TextEdit record (SE FDHD).
| Pascal: function TEStylNew(dest, view: Rect): TEHandle;
| Like _TENew but also allocates the StyleRec, element handle,
| and lineHeights handle, and marks the TERec as styled by
| setting teStylFlag (0x50) = 0xFFFF and lineHeight/ascent =
| 0xFFFF (force recalc on first draw). Plus has no styled-TE
| support; this is one of the SE FDHD's TextEdit additions.
| ----------------------------------------------------------
TESTYLNEW:
    LINK        A6,#0x0                         | no local vars
    MOVEM.L     D2-D7/A2-A4,-(A7)               | save registers
    CLR.L       0x10(A6)                        | clear return value (TEHandle)
    MOVEQ.L     #0x68,D0                        | 104 bytes = sizeof(TERec)
    _NewHandleClear                             | allocate zeroed TERec
    BNE.W       TE_RESIZE_SYSERROR              | failed -> SysError
    MOVEA.L     A0,A4                           | A4 = TEHandle
    _HLock                                      | lock TEHandle
    MOVEA.L     (A4),A3                         | A3 = dereferenced TERec
    MOVEQ.L     #0x0,D0                         | zero-length handle
    _NewHandle                                  | empty text buffer
    BNE.W       TE_RESIZE_SYSERROR              | failed -> SysError
    MOVE.L      A0,0x3E(A3)                     | TERec.hText = empty text handle
    LEA.L       (A3),A0                         | A0 = TERec (destRect at offset 0)
    MOVEA.L     0xC(A6),A2                      | A2 = destRect parameter
    MOVE.L      (A2)+,(A0)+                     | copy destRect.topLeft
    MOVE.L      (A2)+,(A0)+                     | copy destRect.botRight
    MOVEA.L     0x8(A6),A2                      | A2 = viewRect parameter
    MOVE.L      (A2)+,(A0)+                     | copy viewRect.topLeft
    MOVE.L      (A2)+,(A0)+                     | copy viewRect.botRight
    MOVE.W      #0xFFFF,0x50(A3)                | mark TERec as styled (teStylFlag)
    MOVEQ.L     #0x1C,D0                        | 28 bytes = StyleRec header
    BSR.W       TE_RESIZE_AND_DEREF             | allocate StyleRec handle
    MOVE.L      A0,0x4A(A3)                     | TERec.styleHandle = StyleRec
    MOVEQ.L     #0x12,D0                        | 18 bytes = first element entry
    BSR.W       TE_RESIZE_AND_DEREF             | allocate elementHandle
    MOVEA.L     0x4A(A3),A2                     | A2 = StyleRec handle
    MOVEA.L     (A2),A2                         | A2 = StyleRec ptr
    MOVE.L      A0,0x4(A2)                      | StyleRec.elementHandle = elements
    MOVEQ.L     #0x0,D0                         | 0 bytes = empty lineHeights
    BSR.W       TE_RESIZE_AND_DEREF             | allocate lineHeights handle
    MOVEA.L     A0,A1                           | A1 = lineHeights handle
    MOVEA.L     0x4A(A3),A0                     | A0 = StyleRec handle
    MOVEA.L     (A0),A0                         | A0 = StyleRec ptr
    MOVE.L      A1,0x8(A0)                      | StyleRec.lineHeights = handle
    MOVEA.L     (A5),A1                         | A1 = app globals
    MOVEA.L     (A1),A1                         | A1 = current GrafPort
    MOVE.L      A1,0x52(A3)                     | teGrafPort = current port
    MOVE.W      0x48(A1),0x4E(A3)               | copy txMode (font/face from style)
    MOVEQ.L     #0x1,D0                         | initial run count = 1
    BSR.W       TE_INIT_STYLEREC                | initialize first style run
    MOVE.W      #0xFFFF,0x1A(A3)                | teAscent = -1 (force recalc)
    MOVE.W      #0xFFFF,0x18(A3)                | teLineHite = -1 (force recalc)
    MOVE.L      (TEWdBreak).W,0x26(A3)          | install default word-break proc
    LEA.L       DefClikProc(PC),A0              | A0 = default click-loop proc
    MOVE.L      A0,0x2A(A3)                     | teClikProc = default
    MOVEA.L     0x3E(A3),A0                     | A0 = text handle
    _HUnlock                                    | unlock text handle
    MOVEA.L     A4,A0                           | A0 = TEHandle
    _HUnlock                                    | unlock TEHandle
    MOVE.L      A4,0x10(A6)                     | store TEHandle as return value
    MOVEQ.L     #0x8,D0                         | param size = 8 (two rect ptrs)
    BRA.W       TE_EXIT_TAIL                    | -> TE exit
| ----------------------------------------------------------
| TE_RESIZE_AND_DEREF - allocate handle for styled TE without losing
| TERec/text-handle locks across heap compaction.
| In: D0 = size to allocate.
| Out: A0 = new handle (relocked TERec/text after).
| Unlocks TERec and text handle (so heap can move them if
| needed during _NewHandle), then re-locks both, returning
| the new handle in A0.
| Called by: TESTYLNEW, TE_PUT_STYL_SCRAP, TE_FULL_REBUILD_LINESTARTS, TE_PASTE_BODY, TE_STYL_PASTE
| ----------------------------------------------------------
TE_RESIZE_AND_DEREF:
    MOVE.L      D0,-(A7)                        | save requested size
    MOVEA.L     0x3E(A3),A0                     | A0 = text handle
    _HUnlock                                    | unlock text handle
    MOVEA.L     A4,A0                           | A0 = TEHandle
    _HUnlock                                    | unlock TEHandle
    MOVE.L      (A7)+,D0                        | restore size
    _NewHandle                                  | allocate new handle
    BNE.W       TE_RESIZE_SYSERROR              | failed -> SysError
    MOVE.L      A0,-(A7)                        | save new handle
    MOVEA.L     A4,A0                           | A0 = TEHandle
    _HLock                                      | re-lock TEHandle
    MOVEA.L     (A4),A3                         | A3 = TERec (may have moved)
    MOVEA.L     0x3E(A3),A0                     | A0 = text handle
    _HLock                                      | re-lock text handle
    MOVEA.L     (A7)+,A0                        | A0 = new handle (return value)
    RTS                                         | return from TE_RESIZE_AND_DEREF
| ----------------------------------------------------------
| _TEUpdate ($A9D3) - redraw text within an update rectangle.
| Pascal: procedure TEUpdate(updateRect: Rect; hTE: TEHandle);
| Called during window updates to redraw the text inside the
| supplied update rect (typically the intersection of the
| update region with the TERec.viewRect).
| ----------------------------------------------------------
TEUPDATE:
    BSR.W       TE_PROLOGUE_NODISP              | set up TE state (8 bytes params)
    MOVEA.L     (A2)+,A0                        | A0 = update rect ptr (param)
    BSR.W       TESETALIGNMENT_CONT             | redraw text within update rect
    BRA.W       TESCROLL_EPILOGUE               | -> TE exit (8 bytes)
| ----------------------------------------------------------
| TEUPDATE_CONT - get word bounds if double-click.
| In: D5 = double-click flag (bit 31), D6 = char offset.
| Out: D0,D1 = word start/end if double-click else D6,D6.
| ----------------------------------------------------------
TEUPDATE_CONT:
    MOVE.W      D6,D0                           | D0 = char offset (click position)
    MOVE.W      D6,D1                           | D1 = same (default: single char)
    TST.L       D5                              | double-click active?
    BPL.B       TEUPDATE_EXIT                   | no -> return single char range
    BSR.W       TEDELETE_CONT_3                 | expand to word boundaries -> D0,D1
TEUPDATE_EXIT:
    RTS                                         | return calculated click offset
| ----------------------------------------------------------
| TEUPDATE_CONT_2 - toggle highlight on the current selection.
| Called by both _TEActivate/Deactivate and _TESetSelect to
| draw or erase the selection highlight rectangle. Skips if
| TERec is inactive.
| ----------------------------------------------------------
TEUPDATE_CONT_2:
    TST.B       0x24(A3)                        | is TERec active?
    BEQ.B       TEUPDATE_EXIT                   | no -> nothing to highlight
    MOVEM.W     0x20(A3),D3-D4                  | D3=teSelStart, D4=teSelEnd
    MOVEQ.L     #0x1,D7                         | D7=1: highlight/unhighlight mode
    BRA.W       P_doTEDoText                    | -> draw/erase selection hilite
| ----------------------------------------------------------
| _TEClick ($A9D4) - handle a mouse click in a TextEdit field.
| Pascal: procedure TEClick(pt: Point; extend: BOOLEAN; hTE: TEHandle);
| Sets selection, handles double-click word selection, and
| tracks the mouse drag (extending selection until release).
| ----------------------------------------------------------
TECLICK:
    BSR.W       TE_PROLOGUE_NODISP              | set up TE state (A3, A6 frame)
    MOVE.L      0xE(A6),0x1C(A3)                | save click point in teSelPoint
    BSR.W       TECLICK_CONT_5                  | convert point to char offset -> D6
    BSR.W       TE_CARET_ERASE                  | hide caret if visible
    SUBQ.W      #0x4,A7                         | room for tick count result
    _TickCount                                  | get current tick count
    MOVE.L      (A7)+,D0                        | D0 = current ticks
    SUB.L       0x2E(A3),D0                     | D0 = elapsed since last click
    CMP.L       (DoubleTime).W,D0               | within double-click interval?
    SLE.B       D5                              | D5 = $FF if double-click timing
    CMP.W       0x32(A3),D6                     | same char position as last click?
    SEQ.B       D1                              | D1 = $FF if same position
    AND.B       D1,D5                           | D5 = double-click (time AND position)
    ROR.L       #0x8,D5                         | shift flag to high byte
    MOVE.W      D6,0x32(A3)                     | save click position for next time
    TST.B       0xC(A6)                         | extend flag (shift-click)?
    BEQ.B       TECLICK_UNHIGHLIGHT             | no -> start fresh selection
    MOVEM.W     0x20(A3),D0-D1                  | D0=teSelStart, D1=teSelEnd
    CMP.W       D6,D0                           | click before selStart?
    BCC.B       TECLICK_NO                      | no -> extend from selEnd
    MOVEA.W     D0,A2                           | A2 = anchor at selStart
    MOVEA.W     D0,A4                           | A4 = anchor at selStart
    BRA.B       TECLICK_AFTER_ANCHOR            | -> update with new position
TECLICK_NO:
    MOVEA.W     D1,A2                           | A2 = anchor at selEnd
    MOVEA.W     D1,A4                           | A4 = anchor at selEnd
TECLICK_AFTER_ANCHOR:
    MOVE.W      D6,D5                           | D5 = current tracking position
    BRA.B       TECLICK_CONT_2                  | -> update selection highlighting
TECLICK_UNHIGHLIGHT:
    BSR.B       TEUPDATE_CONT_2                 | unhighlight current selection
    MOVEQ.L     #0x4,D2                         | D2=4: findWord mode (initial click)
    BSR.B       TEUPDATE_CONT                   | get word bounds if double-click
    MOVEM.W     D0-D1,0x20(A3)                  | set teSelStart/teSelEnd
    MOVEA.W     D0,A2                           | A2 = selection anchor start
    MOVEA.W     D1,A4                           | A4 = selection anchor end
    MOVE.W      D6,D5                           | D5 = current tracking position
    MOVE.B      0x46(A3),0x47(A3)               | save teLftClick to teLftCaret
    BSR.W       TE_CARET_RESTORE                | set caret state if insertion point
    BSR.B       TEUPDATE_CONT_2                 | highlight new selection
TECLICK_LOOP:
    MOVE.L      0x2A(A3),D0                     | D0 = teClikProc (click loop proc)
    BEQ.B       TECLICK_EMPTY                   | nil -> use default WaitMouseUp
    MOVEA.L     D0,A0                           | A0 = click loop proc
    JSR         (A0)                            | call app's click loop; Z=abort
    BEQ.B       TECLICK_SET_CARET               | app says stop -> end tracking
TECLICK_EMPTY:
    CLR.W       -(A7)                           | space for WaitMouseUp result
    _WaitMouseUp                                | wait for mouse movement or release
    TST.W       (A7)+                           | still tracking?
    BEQ.B       TECLICK_SET_CARET               | mouse released -> end tracking
    PEA.L       0x1C(A3)                        | push ptr to teSelPoint for GetMouse
    _GetMouse                                   | read current mouse position
    BSR.B       TECLICK_CONT_5                  | convert point to char offset -> D6
    CMP.W       D6,D5                           | position changed?
    BEQ.B       TECLICK_LOOP                    | same -> keep waiting
    BSR.W       TE_CARET_ERASE                  | hide caret before hilite update
TECLICK_CONT_2:
    MOVEQ.L     #0x8,D2                         | D2=8: findWord mode (drag tracking)
    BSR.W       TEUPDATE_CONT                   | expand to word bounds if double-click
    LEA.L       0x22(A3),A0                     | A0 -> teSelEnd field
    CMPA.W      D6,A4                           | click before anchor end?
    BCS.B       TECLICK_OK                      | yes -> extending forward
    MOVE.W      -(A0),D3                        | D3.W = old teSelStart
    MOVE.W      D0,(A0)+                        | teSelStart = new start
    MOVE.W      D0,D4                           | D4.W = new start
    SWAP.W      D3                              | D3: old selStart in high word
    SWAP.W      D4                              | D4: new start in high word
    MOVE.W      A4,D3                           | D3.W = anchor position
    MOVE.W      (A0)+,D4                        | D4.W = old teSelEnd
    MOVE.W      A4,-(A0)                        | teSelEnd = anchor
    BRA.B       TECLICK_CONT_3                  | -> XOR hilite for both ranges
| ----------------------------------------------------------
| TECLICK_OK - extend selection forward (drag past anchor).
| ----------------------------------------------------------
TECLICK_OK:
    CMPA.W      D6,A2                           | click still within anchor range?
    BHI.B       TECLICK_OK_2                    | yes -> no hilite change needed
    MOVE.W      (A0)+,D3                        | D3.W = old teSelEnd
    MOVE.W      D1,-(A0)                        | teSelEnd = new end
    MOVE.W      D1,D4                           | D4.W = new end
    SWAP.W      D3                              | D3: old selEnd in high word
    SWAP.W      D4                              | D4: new end in high word
    MOVE.W      -(A0),D3                        | D3.W = old teSelStart
    MOVE.W      A2,D4                           | D4.W = anchor start
    MOVE.W      A2,(A0)+                        | teSelStart = anchor
TECLICK_CONT_3:
    MOVEQ.L     #0x1,D7                         | D7=1: highlight/unhighlight mode
    BSR.W       P_doTEDoText                    | XOR hilite for first changed range
    SWAP.W      D3                              | swap to second range pair
    SWAP.W      D4                              | swap to second range pair
    BSR.W       P_doTEDoText                    | XOR hilite for second changed range
TECLICK_OK_2:
    MOVE.W      D6,D5                           | D5 = updated tracking position
    BRA.B       TECLICK_LOOP                    | -> continue tracking loop
TECLICK_SET_CARET:
    BSR.W       TE_CARET_RESTORE                | set caret state if insertion point
    SUBQ.W      #0x4,A7                         | room for tick count result
    _TickCount                                  | get tick count for next double-click
    MOVE.L      (A7)+,0x2E(A3)                  | save click time
    MOVEQ.L     #0xA,D0                         | param size = 10 bytes
    BRA.W       TE_EXIT_4PARAM                  | -> TE exit
| ----------------------------------------------------------
| TECLICK_CONT_5 - convert teSelPoint to character offset (D6).
| Uses teSelPoint.v to find which line the click lies on
| (TE_PIXELY_TO_LINE); if past last line returns teLength, if before
| first line returns 0; otherwise calls P_doTEDoText with
| D7=0 (pixel-to-char mode) to find the offset within line.
| ----------------------------------------------------------
TECLICK_CONT_5:
    MOVE.W      0x1C(A3),D0                     | D0 = click vertical coord (teSelPoint.v)
    BSR.W       TE_PIXELY_TO_LINE               | convert to line number -> D0
    BGE.B       TECLICK_CONT_6                  | beyond last line -> selEnd
    ADD.W       D0,D0                           | word offset into lineStarts array
    BPL.B       TECLICK_CONT_7                  | valid line -> measure char offset
    MOVEQ.L     #0x0,D6                         | before first line -> offset 0
    RTS                                         | return offset 0 for click before first line
| ----------------------------------------------------------
| TECLICK_CONT_6 - click past last line returns teLength.
| ----------------------------------------------------------
TECLICK_CONT_6:
    MOVE.W      0x3C(A3),D6                     | D6 = teLength
    RTS                                         | return offset teLength for click past end
TECLICK_CONT_7:
    MOVEM.W     0x60(A3,D0.W),D3-D4             | D3=lineStart, D4=nextLineStart
    MOVEQ.L     #0x0,D7                         | D7=0: pixel-to-char conversion mode
    BSR.W       P_doTEDoText                    | find char offset at click.h -> D0
    MOVE.W      D0,D6                           | D6 = character offset at click point
    RTS                                         | return measured character offset
| ----------------------------------------------------------
| P_Pixel2Char - hookable trampoline to the pixel-to-char proc
| stored at lowmem 0x798. Tail-calls the hook via stacked RTS:
| pushes (0x798) on top of the BSR return address, then RTS
| jumps to the hook with the original caller's return address
| left on the stack.
| ----------------------------------------------------------
P_Pixel2Char:
    MOVE.L      (0x798).W,-(A7)                 | push hook proc address on stack
    RTS                                         | tail-call to hook
| ----------------------------------------------------------
| VPIXEL2CHAR - default pixel-to-char converter for variable-
| width fonts. Measures all char widths on the run via
| _MeasureText, then locates which char's rect contains the
| target pixel.
| In: D0 = char count, D1 = target pixel offset, A0 = text ptr.
| Out: D0 = pixel position of char, D1 = char index,
|      D2 = side flag (1=left half, 0=right half).
| Buffer for char widths comes from the stack if >=1KB free,
| otherwise from a temporary _NewPtr.
| ----------------------------------------------------------
VPIXEL2CHAR:
    MOVEM.L     D3-D4/A4,-(A7)                  | save scratch registers
    MOVE.W      D1,D3                           | D3 = target pixel offset
    MOVEQ.L     #0x0,D4                         | clear D4
    MOVE.W      D0,D4                           | D4 = char count
    ADDQ.W      #0x1,D0                         | (count+1) entries needed
    EXT.L       D0                              | sign-extend to long
    ADD.L       D0,D0                           | times 2 = byte size
    MOVE.L      D0,D1                           | D1 = bytes needed
    _StackSpace                                 | D0 = available stack bytes
    SUB.L       D1,D0                           | D0 = stack left after alloc
    CMPI.L      #0x400,D0                       | at least 1KB cushion?
    BCS.B       PIXELTOCHAR_HEAP_ALLOC          | no -> heap-allocate buffer
    SUBA.L      D1,A7                           | reserve buffer on stack
    MOVEA.L     A7,A4                           | A4 = widths buffer
    BRA.B       PIXELTOCHAR_MEASURE             | -> measure text
PIXELTOCHAR_HEAP_ALLOC:
    MOVE.L      A0,-(A7)                        | save text ptr
    _NewPtr                                     | allocate widths buffer
    MOVEA.L     A0,A4                           | A4 = widths buffer
    MOVEA.L     (A7)+,A0                        | restore text ptr
    MOVEQ.L     #0x0,D1                         | D1=0 means heap-allocated
    TST.W       D0                              | _NewPtr OK?
    BEQ.B       PIXELTOCHAR_MEASURE             | yes -> measure
    _SysError                                   | failed -> SysError
PIXELTOCHAR_MEASURE:
    MOVE.L      D1,-(A7)                        | push numerator extension (0)
    MOVE.W      D4,-(A7)                        | push char count
    MOVE.L      A0,-(A7)                        | push text ptr
    MOVE.L      A4,-(A7)                        | push widths buffer ptr
    _MeasureText                                | fill cumulative widths
    MOVE.W      D4,D1                           | D1 = char count (search index)
    ADD.L       D4,D4                           | D4 = byte offset to last entry
    ADDA.L      D4,A4                           | A4 -> last widths entry
    CMP.W       (A4),D3                         | target past line end?
    BGT.B       PIXELTOCHAR_CLAMP_ZERO          | yes -> clamp to 0
PIXELTOCHAR_SCAN_BACK:
    CMP.W       -(A4),D3                        | scan backwards for char rect
    BGE.B       PIXELTOCHAR_FOUND_CHAR          | found containing char
    SUBQ.W      #0x1,D1                         | step to previous char
    BNE.B       PIXELTOCHAR_SCAN_BACK           | continue search
    ADDQ.W      #0x1,D1                         | clamp to 1 (first char)
PIXELTOCHAR_FOUND_CHAR:
    MOVE.W      0x2(A4),D2                      | D2 = right edge of char
    MOVE.W      (A4),D4                         | D4 = left edge of char
    SUB.W       D4,D2                           | width
    ASR.W       #0x1,D2                         | half-width
    ADD.W       D2,D4                           | mid-point pixel
    MOVEQ.L     #0x1,D0                         | (preset for high word)
    SWAP.W      D0                              | (slot 1 in long)
    MOVEQ.L     #0x0,D2                         | side flag = right half
    CMP.W       D4,D3                           | target past mid-point?
    BGE.B       PIXELTOCHAR_FINALIZE            | yes -> right half
    MOVEQ.L     #0x1,D2                         | left half
    BRA.B       PIXELTOCHAR_FINALIZE            | -> finalize
PIXELTOCHAR_CLAMP_ZERO:
    MOVEQ.L     #0x0,D0                         | clamp pixel pos = 0
    MOVEQ.L     #0x0,D2                         | side flag = right
PIXELTOCHAR_FINALIZE:
    MOVE.W      (A4),D0                         | D0 = pixel pos of char's left edge
    MOVE.L      (A7)+,D3                        | restore stack/heap flag
    BEQ.B       PIXELTOCHAR_DISPOSE_BUF         | 0 -> heap-allocated, dispose
    ADDA.L      D3,A7                           | otherwise pop stack buffer
    BRA.B       VPIXEL2CHAR_EXIT                | -> restore regs
PIXELTOCHAR_DISPOSE_BUF:
    MOVEM.L     D0-D2,-(A7)                     | save results
    MOVEA.L     A4,A0                           | A0 = heap buffer
    _DisposePtr                                 | free buffer
    MOVEM.L     (A7)+,D0-D2                     | restore results
VPIXEL2CHAR_EXIT:
    MOVEM.L     (A7)+,D3-D4/A4                  | restore scratch registers
    RTS                                         | return from VPIXEL2CHAR
| ----------------------------------------------------------
| PIXELTOCHAR_STY_ENTRY - P_TEDoText D7=0 path: pixel-to-char on a line.
| In: D5 = target pixel position, A2 = lineStarts entry.
| Output: char offset of the click position on the line.
| For unstyled TE: single _MeasureText call covers the line.
| For styled TE: walks each style run, measures each, and
| accumulates pixel positions until the target is found.
| ----------------------------------------------------------
PIXELTOCHAR_STY_ENTRY:
    BSR.W       TECLICK_CONT_10                 | clamp char range to viewable line
    MOVE.W      (A2),D3                         | D3 = line start char offset
    MOVE.W      D3,D4                           | D4 = same (running offset)
    BSR.W       TEDOTEXT_INIT_SCAN_STATE        | set up text scan state
    MOVE.W      (A2),D7                         | D7 = line start char offset
    MOVE.W      0x1E(A3),D5                     | D5 = teRect.right (max pixel)
    SUB.W       0x12(A3),D5                     | D5 = available width
    MOVE.W      0x12(A3),0x16(A3)               | save teRectLeft to teRectLeftSave
    MOVE.W      #0x8002,0x12(A3)                | mark as in-progress (pixel mode)
    MOVE.W      0x2(A2),D6                      | D6 = next line's start char offset
    TST.W       0x50(A3)                        | styled TE?
    BMI.B       PIXELTOCHAR_STY_MULTI_RUN       | yes -> walk style runs
    MOVEQ.L     #0x1,D2                         | unstyled: 1 run only
    MOVE.W      D3,D1                           | D1 = run start = line start
    MOVE.W      D6,D0                           | D0 = run end = line end
    BRA.B       PIXELTOCHAR_STY_MEASURE         | -> measure single run
PIXELTOCHAR_STY_MULTI_RUN:
    MOVE.W      D3,D0                           | D0 = line start char
    MOVE.W      D6,D1                           | D1 = line end char
    BSR.W       TE_LOCATE_STYLERUNS             | locate style runs covering range
    MOVEA.L     A0,A2                           | A2 = first run pointer
    MOVE.W      D0,D2                           | D2 = run count remaining
    MOVEA.L     0x4A(A3),A0                     | A0 = StyleRec handle
    _HLock                                      | lock StyleRec for traversal
    MOVEA.L     A2,A0                           | A0 = first run pointer
PIXELTOCHAR_STY_RUN_LOOP:
    MOVEA.L     A0,A2                           | A2 = current run
    BSR.W       SetPortFromStyleRun             | apply run's font/style to port
    MOVE.W      (A0),D1                         | D1 = run start char offset
    ADDQ.L      #0x4,A0                         | step to next run header
    MOVE.W      (A0),D0                         | D0 = next run's start (run end)
    CMP.W       D3,D1                           | run start before line start?
    BCC.B       PIXELTOCHAR_STY_CLAMP_START     | no -> use as-is
    MOVE.W      D3,D1                           | clamp run start to line start
PIXELTOCHAR_STY_CLAMP_START:
    MOVE.W      D1,D7                           | D7 = current run start
    CMP.W       D0,D6                           | run end after line end?
    BCC.B       PIXELTOCHAR_STY_MEASURE         | no -> use as-is
    MOVE.W      D6,D0                           | clamp run end to line end
PIXELTOCHAR_STY_MEASURE:
    MOVE.W      D2,-(A7)                        | save run count
    SUB.W       D1,D0                           | D0 = chars in this run
    MOVEA.L     0x3E(A3),A0                     | A0 = text handle
    MOVEA.L     (A0),A0                         | A0 = text ptr
    ADDA.W      D1,A0                           | A0 = text + run start
    MOVE.W      D5,D1                           | D1 = remaining width to find
    MOVEQ.L     #0x0,D2                         | D2 = 0 (search initialize)
    BSR.W       P_Pixel2Char                    | measure this run via hookable proc
    ADD.W       D0,0x16(A3)                     | accumulate pixel pos in line state
    SUB.W       D0,D5                           | D5 -= pixels consumed
    ADD.W       D1,D7                           | D7 += chars found in this run
    SWAP.W      D0                              | check found-flag (high word)
    TST.W       D0                              | did we find target?
    BNE.B       PIXELTOCHAR_STY_CR_CHECK        | yes -> finalize
    ADD.W       D1,D4                           | not found in this run; advance D4
    CMP.W       D4,D6                           | reached line end?
    BLS.B       PIXELTOCHAR_STY_PAST_END        | yes -> end-of-line case
    MOVEA.L     A2,A0                           | A0 = current run pointer
    MOVE.W      (A7)+,D2                        | restore run count
    BSR.W       TE_ADVANCE_STYLERUN             | advance to next style run
    SUBQ.W      #0x1,D2                         | one less run remaining
    BNE.B       PIXELTOCHAR_STY_RUN_LOOP        | more runs -> continue
    MOVEQ.L     #0x1,D7                         | exhausted runs -> char index 1
    BRA.B       PIXELTOCHAR_STY_LEFT_SIDE       | -> finalize as right-side
PIXELTOCHAR_STY_PAST_END:
    MOVE.W      #0x7FFE,0x16(A3)                | mark as past line end
    MOVEQ.L     #0x0,D2                         | side flag = right
    MOVEA.L     0x3E(A3),A0                     | A0 = text handle
    MOVEA.L     (A0),A0                         | A0 = text ptr
    CMPI.B      #0xD,-0x1(A0,D7.W)              | char before D7 a CR?
    BNE.B       PIXELTOCHAR_STY_CR_CHECK        | no -> right-side caret
    MOVEQ.L     #0x1,D2                         | yes -> left-side caret (after CR)
PIXELTOCHAR_STY_CR_CHECK:
    ADDQ.L      #0x2,A7                         | discard saved run count
    SF.B        0x46(A3)                        | teLftClick = false
    TST.W       D2                              | left-side?
    BEQ.B       PIXELTOCHAR_STY_FINALIZE        | no -> finalize
PIXELTOCHAR_STY_LEFT_SIDE:
    SUBQ.W      #0x1,D7                         | adjust char index for left-side
    ST.B        0x46(A3)                        | teLftClick = true
PIXELTOCHAR_STY_FINALIZE:
    TST.W       0x50(A3)                        | styled TE?
    BPL.B       PIXELTOCHAR_STY_EXIT            | no -> skip unlock
    MOVEA.L     0x4A(A3),A0                     | A0 = StyleRec handle
    _HUnlock                                    | unlock StyleRec
PIXELTOCHAR_STY_EXIT:
    MOVE.W      D7,D0                           | D0 = result char index
    BRA.W       TECLICK_EXIT_2                  | -> P_TEDoText exit
| ----------------------------------------------------------
| TEDOTEXT_DRAW_BEGIN - P_TEDoText D7=-1 path: redraw all visible lines.
| Used by _TEUpdate. Walks each line in the destRect, erases
| trailing space, _MoveTo's the baseline, and _DrawText's the
| line content (with style-run iteration for styled TE).
| ----------------------------------------------------------
TEDOTEXT_DRAW_BEGIN:
    BSR.W       XTRIMMEASURE_CONT_3             | save GrafPort font state
    BSR.W       TECLICK_CONT_10                 | clamp char range, save regs
    BSR.W       TEDOTEXT_INIT_SCAN_STATE        | set up text scan state
TEDOTEXT_NEXT_LINE:
    BSR.W       TEDOTEXT_NEXT_VISLINE           | next visible line; CCR set
    BLS.W       TECLICK_EXIT_2                  | past last visible line -> exit
    BSR.W       TEDOTEXT_LINE_BOUNDS            | get line bounds in port coords
    TST.W       (TESysJust).W                   | right-justified (RTL)?
    BEQ.B       TEDOTEXT_NORMAL_DRAW            | no -> normal draw
    MOVE.W      #0x8002,0x12(A3)                | mark RTL state
TEDOTEXT_NORMAL_DRAW:
    MOVE.W      D4,D6                           | D6 = line end char
    BSR.W       TEDELETE_CONT_2                 | erase line tail beyond text
    MOVE.W      -0x2(A6),-(A7)                  | push line baseline (saved local)
    MOVE.W      0x10(A3),-(A7)                  | push teRectLeft
    MOVE.W      0x1A(A3),D0                     | D0 = teAscent
    TST.W       0x50(A3)                        | styled TE?
    BMI.B       TEDOTEXT_NEG_ASCENT             | yes -> per-run drawing
    ADD.W       D0,(A7)                         | add ascent to baseline
    _MoveTo                                     | move pen to line start
    MOVEA.L     0x3E(A3),A0                     | A0 = text handle
    MOVEA.L     (A0),A0                         | A0 = text ptr
    ADDA.L      D3,A0                           | A0 = text + line start
    MOVE.L      A0,-(A7)                        | push text ptr
    CLR.W       -(A7)                           | push offset (0)
    MOVE.W      D4,-(A7)                        | push char count = lineEnd
    SUB.W       D3,(A7)                         | char count = lineEnd - lineStart
    _DrawText                                   | draw the line
    BRA.W       TEDOTEXT_LINE_DONE              | -> next line
TEDOTEXT_NEG_ASCENT:
    TST.W       D0                              | teAscent < 0?
    BPL.B       TEDOTEXT_USE_ASCENT             | no -> use as-is
    BSR.W       P_TEDOTEXT_CONT_2               | get current line index
    EXT.L       D0                              | sign-extend
    LSL.L       #0x2,D0                         | times 4 (entry size)
    MOVEA.L     0x4A(A3),A0                     | A0 = StyleRec handle
    MOVEA.L     (A0),A0                         | A0 = StyleRec ptr
    MOVEA.L     0x8(A0),A0                      | A0 = lineHeights handle
    MOVEA.L     (A0),A0                         | A0 = lineHeights array
    MOVE.W      0x2(A0,D0.L),D0                 | D0 = ascent for this line
TEDOTEXT_USE_ASCENT:
    ADD.W       D0,(A7)                         | add per-line ascent
    _MoveTo                                     | move pen to line baseline
    MOVE.W      D3,D0                           | D0 = line start char
    MOVE.W      D4,D1                           | D1 = line end char
    BSR.W       TE_LOCATE_STYLERUNS             | locate style runs covering range
    MOVE.W      D0,D2                           | D2 = run count
TEDOTEXT_DRAW_RUN:
    MOVEA.L     A0,A4                           | A4 = current run pointer
    BSR.W       SetPortFromStyleRun             | apply run's font/style to port
    MOVE.W      (A0),D0                         | D0 = run start char
    ADDQ.W      #0x4,A0                         | step to next run header
    MOVE.W      D6,D4                           | D4 = lineEnd
    CMP.W       (A0),D6                         | line end past run end?
    BCS.B       TEDOTEXT_CLAMP_DRAW_END         | no -> draw to lineEnd
    MOVE.W      (A0),D4                         | clamp draw end to run end
TEDOTEXT_CLAMP_DRAW_END:
    MOVE.W      D2,-(A7)                        | save run count
    MOVEA.L     0x3E(A3),A0                     | A0 = text handle
    MOVEA.L     (A0),A0                         | A0 = text ptr
    CMP.W       D3,D0                           | run start before line start?
    BCC.B       TEDOTEXT_USE_RUN_START          | no -> use as-is
    MOVE.W      D3,D0                           | clamp run start to line start
TEDOTEXT_USE_RUN_START:
    ADDA.W      D0,A0                           | A0 = text + draw start
    MOVE.L      A0,-(A7)                        | push text ptr
    CLR.W       -(A7)                           | push offset (0)
    MOVE.W      D4,-(A7)                        | push char count = drawEnd
    SUB.W       D0,(A7)                         | count = drawEnd - drawStart
    _DrawText                                   | draw this style run's chars
    MOVEA.L     A4,A0                           | A0 = current run pointer
    MOVE.W      (A7)+,D2                        | restore run count
    BSR.W       TE_ADVANCE_STYLERUN             | advance to next run
    SUBQ.W      #0x1,D2                         | one less run
    BNE.B       TEDOTEXT_DRAW_RUN               | more runs -> continue
TEDOTEXT_LINE_DONE:
    BSR.W       P_TEDOTEXT_CONT_2               | get current line index
    ADDQ.W      #0x1,D0                         | advance to next line
    BSR.W       TEDOTEXT_ADV_PAST_LINES         | set new line index
    MOVE.W      (A2),D3                         | D3 = next line start
    BRA.W       TEDOTEXT_NEXT_LINE              | -> draw next line
| ----------------------------------------------------------
| TECLICK_EXIT_2 - shared P_TEDoText exit. Restore registers,
| unlink frame, return current GrafPort in A0.
| ----------------------------------------------------------
TECLICK_EXIT_2:
    MOVEM.L     (A7)+,D2-D7/A2-A4               | restore registers
    UNLK        A6                              | tear down frame
    MOVEA.L     (A5),A0                         | A0 = QD globals handle
    MOVEA.L     (A0),A0                         | A0 = current GrafPort
    RTS                                         | return from P_TEDoText
| ----------------------------------------------------------
| TEDELETE_CONT_2 - erase the tail of a line beyond the drawn text.
| Computes the pixel position past the last char on the line
| (using _TextWidth for styled TE, otherwise teRectLeft) and
| erases everything to the right edge via _EraseRect.
| ----------------------------------------------------------
TEDELETE_CONT_2:
    MOVE.W      0x12(A3),-(A7)                  | save current teRectLeft
    CMP.W       (A2),D3                         | line empty (start == end)?
    BEQ.B       TEDOTEXT_ERASE_TAIL             | yes -> no text width to add
    TST.W       0x50(A3)                        | styled TE?
    BPL.B       TEDOTEXT_EXTEND_LEFT            | no -> use current font
    MOVE.W      D3,D0                           | D0 = char position
    MOVE.W      D0,D1                           | D1 = same
    BSR.W       TE_LOCATE_STYLERUNS             | locate style run for D3
    BSR.W       SetPortFromStyleRun             | apply run's font/style
TEDOTEXT_EXTEND_LEFT:
    SUBQ.L      #0x2,A7                         | room for _TextWidth result
    MOVEA.L     0x3E(A3),A0                     | A0 = text handle
    MOVE.L      (A0),-(A7)                      | push text ptr
    MOVE.W      D3,-(A7)                        | push offset (line start)
    MOVE.W      #0x1,-(A7)                      | push count (1 char)
    _TextWidth                                  | measure 1-char prefix width
    MOVE.W      (A7)+,D0                        | D0 = width result
    ADD.W       D0,0x12(A3)                     | extend teRectLeft past text
TEDOTEXT_ERASE_TAIL:
    PEA.L       0x10(A3)                        | push teLine rect
    _EraseRect                                  | erase line tail
    MOVE.W      (A7)+,0x12(A3)                  | restore teRectLeft
    RTS                                         | return from TEDELETE_CONT_2
| ----------------------------------------------------------
| TE_LOCATE_STYLERUNS - locate first style run covering chars D0..D1.
| Out: A0 = first run, D0 = run count covering range.
| For RTL text, advances A0 to last run (descending order).
| Called by: PIXELTOCHAR_STY_MULTI_RUN, TEDOTEXT_USE_ASCENT, TEDELETE_CONT_2, TEDOTEXT_LINE_BOUNDS, TE_MEASURE_RANGE
| ----------------------------------------------------------
TE_LOCATE_STYLERUNS:
    BSR.W       DateToSeconds                   | binary-search StyleRec
    BSR.W       CountRunsBefore                 | count runs in range
    TST.W       (TESysJust).W                   | RTL?
    BEQ.B       TE_LOCATE_STYLERUNS_RTS         | no -> use first run
    MOVEQ.L     #0x0,D1                         | clear D1
    MOVE.W      D0,D1                           | D1 = count
    SUBQ.W      #0x1,D1                         | last entry index
    LSL.L       #0x2,D1                         | bytes (4 bytes/run)
    ADDA.L      D1,A0                           | A0 -> last run
TE_LOCATE_STYLERUNS_RTS:
    RTS                                         | return from TE_LOCATE_STYLERUNS
| ----------------------------------------------------------
| TE_ADVANCE_STYLERUN - advance/back style run pointer by one entry.
| LTR text: A0 += 4 (forward); RTL: A0 -= 4 (backward).
| ----------------------------------------------------------
TE_ADVANCE_STYLERUN:
    TST.W       (TESysJust).W                   | RTL?
    BEQ.B       TE_ADVANCE_STYLERUN_LTR         | no -> forward
    SUBQ.L      #0x4,A0                         | RTL: previous run
    BRA.B       TE_ADVANCE_STYLERUN_RTS         | -> return
TE_ADVANCE_STYLERUN_LTR:
    ADDQ.L      #0x4,A0                         | LTR: next run
TE_ADVANCE_STYLERUN_RTS:
    RTS                                         | return from TE_ADVANCE_STYLERUN
| ----------------------------------------------------------
| TEDOTEXT_NEXT_VISLINE - check if next line is in viewable range.
| Out: D4 = clamped line end, CCR = compare D5 vs D3
| (LS=past visible, GT=more lines to draw).
| ----------------------------------------------------------
TEDOTEXT_NEXT_VISLINE:
    MOVE.W      D5,D4                           | D4 = max viewable position
    CMP.W       0x2(A2),D4                      | lineStart[next] < max?
    BCS.B       TEDOTEXT_LINE_BOUNDS_OK         | yes -> use lineStart[next]
    MOVE.W      0x2(A2),D4                      | clamp to lineStart[next]
TEDOTEXT_LINE_BOUNDS_OK:
    BSR.W       TEDOTEXT_REPOS_PEN              | reposition pen for line
    CMP.W       D3,D5                           | compare for caller branch
    RTS                                         | return from TEDOTEXT_NEXT_VISLINE
| ----------------------------------------------------------
| TECLICK_CONT_10 - common P_TEDoText prologue.
| Pops return address, saves D2-D7/A2-A4, ensures D3 <= D4
| (selStart <= selEnd), clamps to teLength, and locates the
| lineStarts entry for D3 via TE_ADVANCE_LINESTART. The two embedded
| .byte rows are AND.L instructions to mask top word of D3/D4
| against the line-relative max (lowmem TEPHysMask).
| ----------------------------------------------------------
TECLICK_CONT_10:
    MOVEA.L     (A7)+,A0                        | A0 = saved return address
    MOVEM.L     D2-D7/A2-A4,-(A7)               | save scratch registers
    MOVE.L      A0,-(A7)                        | restore return address on stack
    CMP.W       D3,D4                           | D4 < D3?
    BCC.B       TECLICK_CONT_11                 | no -> already ordered
    EXG         D4,D3                           | yes -> swap so D3<=D4
TECLICK_CONT_11:
    CMP.W       0x3C(A3),D4                     | D4 > teLength?
    BCS.B       TECLICK_OK_5                    | no -> use as-is
    MOVE.W      0x3C(A3),D4                     | clamp to teLength
TECLICK_OK_5:
    LEA.L       0x60(A3),A2                     | A2 = lineStarts array
    .byte 0xC8,0xBA,0x07,0x86                   | AND.L (TEPHysMask).W,D4 (mask high word)
    MOVE.W      D4,D5                           | D5 = clamped end
    .byte 0xC6,0xBA,0x07,0x80                   | AND.L (TEPMask).W,D3 (mask high word)
    BEQ.B       TECLICK_CONT_10_RTS             | D3 was 0 -> A2 already at line 0
    MOVE.W      D3,D0                           | D0 = char offset
    BSR.W       TE_ADVANCE_LINESTART            | advance A2 to line containing D3
TECLICK_CONT_10_RTS:
    RTS                                         | return from TECLICK_CONT_10
| ----------------------------------------------------------
| TE_ADVANCE_LINESTART - advance lineStarts pointer past D0 char offset.
| Walks A2 forward through lineStarts until lineStart[A2+1] > D0.
| ----------------------------------------------------------
TE_ADVANCE_LINESTART:
    CMP.W       0x2(A2),D0                      | next-line start <= D0?
    BLS.B       TECLICK_FOUND_3                 | yes -> done
    ADDQ.W      #0x2,A2                         | step to next line entry
    BRA.B       TE_ADVANCE_LINESTART            | continue scan
TECLICK_FOUND_3:
    BNE.B       TECLICK_DONE                    | not exact match -> stop here
    ADDQ.W      #0x2,A2                         | match: advance one more
TECLICK_DONE:
    RTS                                         | return from TE_ADVANCE_LINESTART
| ----------------------------------------------------------
| P_doTEDoText - hookable trampoline to TEDoText lowmem.
| Tail-calls (TEDoText) via stacked-RTS pattern.
| ----------------------------------------------------------
| Called by: TECLICK_CONT_3, TEUPDATE_CONT_2, TECLICK_CONT_7, TE_RECALC_LINES_REDRAW, P_TERECAL_CONT_4 (and 3 more)
P_doTEDoText:
    MOVE.L      (TEDoText).W,-(A7)              | push hook proc address
    RTS                                         | tail-call to hook
| ----------------------------------------------------------
| P_TEDoText - default TextEdit core text op.
| In: D7 = mode (0=pixel-to-char, 1=highlight, -1=draw,
|     other=measure char range), D3..D4 = char range or
|     selection, A3 = TERec, A6 = caller's frame ptr.
| Out: result depends on D7; common exit at TECLICK_EXIT_2.
| Locals at -0x2(A6): line baseline coord,
|         at -0x4(A6): per-line state.
| ----------------------------------------------------------
P_TEDoText:
    LINK        A6,#-0x4                        | local vars: 4 bytes
    TST.W       D7                              | D7 = mode
    BEQ.W       PIXELTOCHAR_STY_ENTRY           | mode 0 -> pixel-to-char
    BGT.B       TEHILITE_DRAW_ENTRY             | mode 1 -> highlight selection
    CMPI.W      #0xFFFF,D7                      | mode -1 (draw)?
    BEQ.W       TEDOTEXT_DRAW_BEGIN             | yes -> draw all visible lines
    BSR.B       TECLICK_CONT_10                 | else: measure rect for range
    TST.W       D3                              | D3 == 0 (char 0)?
    BEQ.B       TEDOTEXT_LINE_LEFT              | yes -> use lineStart 0
    CMP.W       (A2),D3                         | D3 starts at a line boundary?
    BNE.B       TEDOTEXT_LINE_LEFT              | no -> normal handling
    MOVE.W      0x3C(A3),D0                     | D0 = teLength
    BEQ.B       TEDOTEXT_LINE_LEFT              | empty TE -> normal
    CMP.W       D0,D3                           | D3 past teLength?
    BCS.B       P_TEDOTEXT_NO                   | no -> check teLftClick
    MOVEA.L     0x3E(A3),A0                     | A0 = text handle
    MOVEA.L     (A0),A0                         | A0 = text ptr
    CMPI.B      #0xD,-0x1(A0,D3.W)              | char before D3 is CR?
    BEQ.B       TEDOTEXT_LINE_LEFT              | yes -> normal handling
    BRA.B       P_TEDOTEXT_NO_2                 | no -> back up to prev line
P_TEDOTEXT_NO:
    TST.B       0x47(A3)                        | teLftCaret set?
    BNE.B       TEDOTEXT_LINE_LEFT              | yes -> normal handling
P_TEDOTEXT_NO_2:
    SUBQ.W      #0x2,A2                         | step back to previous line
| Called by: P_TEDoText, P_TEDOTEXT_NO
TEDOTEXT_LINE_LEFT:
    BSR.W       TEDOTEXT_INIT_SCAN_STATE        | set up text scan state
    BSR.W       TEDOTEXT_NEXT_VISLINE           | next visible line; CCR set
    MOVE.W      -0x2(A6),D0                     | D0 = computed left edge
    MOVE.W      D0,0x16(A3)                     | save to teRectLeftSave
    SUBQ.W      #0x1,D0                         | width = -1 (empty rect)
    MOVE.W      D0,0x12(A3)                     | teRectLeft = computed
    BRA.W       TECLICK_EXIT_2                  | -> exit
| ----------------------------------------------------------
| TEHILITE_DRAW_ENTRY - P_TEDoText D7=1 path: highlight selection range.
| Calls 0x56(A3) (teHiliteHook) once per fully-selected line,
| then handles partial-line highlighting at the boundaries.
| Used for both XOR-toggling selection on activate/deactivate
| and for redrawing the hilite during click+drag tracking.
| ----------------------------------------------------------
TEHILITE_DRAW_ENTRY:
    BSR.W       XTRIMMEASURE_CONT_3             | save GrafPort font state
    BSR.W       TECLICK_CONT_10                 | clamp range, save regs, locate line
    BSR.W       TEDOTEXT_INIT_SCAN_STATE        | set up text scan state
    BSR.W       TEDOTEXT_NEXT_VISLINE           | next visible line; CCR set
    BLS.B       P_TEDOTEXT_LAST_PARTIAL         | past last line -> exit
    BSR.W       TEDOTEXT_LINE_BOUNDS            | get line bounds in port coords
    MOVE.L      0x56(A3),D0                     | D0 = teHiliteHook addr
    BSR.W       XTRIMMEASURE_CONT_7             | invoke hook (paint hilite rect)
    CMP.W       0x2(A2),D5                      | range ends within this line?
    BLS.B       P_TEDOTEXT_LAST_PARTIAL         | yes -> done
    BSR.W       P_TEDOTEXT_CONT_2               | get current line index
    MOVE.W      D0,D1                           | D1 = first line index
    MOVE.W      D5,D0                           | D0 = end-position char offset
    BSR.W       TE_ADVANCE_LINESTART            | locate line containing end
    BSR.W       P_TEDOTEXT_CONT_2               | D0 = end line index
    ADDQ.W      #0x1,D1                         | D1 = first+1 (start of middle)
    CMP.W       D0,D1                           | only 2 lines (no middle)?
    BEQ.B       TEHILITE_END_LINE               | yes -> skip middle band
    MOVE.W      D0,-(A7)                        | save end-line index
    EXG         D0,D1                           | D0=middle-start, D1=middle-end
    MOVE.W      0x14(A3),0x10(A3)               | teRectTop = current pen y
    BSR.W       TE_TOTAL_HEIGHT                 | compute middle-band height
    ADD.W       D0,0x14(A3)                     | advance teRectTop past middle
    MOVE.W      #0x8002,0x12(A3)                | teRectLeft = full-line marker
    MOVE.W      #0x7FFE,0x16(A3)                | teRectLeftSave = past-line marker
    MOVE.L      0x56(A3),D0                     | D0 = teHiliteHook
    BSR.W       XTRIMMEASURE_CONT_7             | invoke hook (paint full-line band)
    MOVE.W      (A7)+,D0                        | restore end-line index
TEHILITE_END_LINE:
    BSR.W       TEDOTEXT_ADV_PAST_LINES         | advance to last line of range
    MOVE.W      (A2),D3                         | D3 = last line's start char
    BSR.W       TEDOTEXT_NEXT_VISLINE           | check viewability; CCR set
    BLS.B       P_TEDOTEXT_LAST_PARTIAL         | past last line -> exit
    BSR.W       TEDOTEXT_LINE_BOUNDS            | get line bounds
    MOVE.L      0x56(A3),D0                     | D0 = teHiliteHook
    BSR.W       XTRIMMEASURE_CONT_7             | invoke hook (paint last partial)
P_TEDOTEXT_LAST_PARTIAL:
    BRA.W       TECLICK_EXIT_2                  | -> P_TEDoText exit
| ----------------------------------------------------------
| TEDOTEXT_LINE_BOUNDS - compute hilite-rect bounds for D3..D4 char
| range on the current line.
| Out: D0/D1 = pixel positions of selStart/selEnd within line.
| Sets teRectLeft = start-marker if D0 == D3 (range begins at
| line start) and teRectLeftSave = past-line-end marker if
| D1 == D4 (range continues past line end).
| ----------------------------------------------------------
TEDOTEXT_LINE_BOUNDS:
    MOVE.W      (A2),D0                         | D0 = lineStart pixel pos
    MOVE.W      0x2(A2),D1                      | D1 = lineEnd pixel pos
    TST.W       0x50(A3)                        | styled TE?
    BPL.B       TEDOTEXT_LINE_BOUNDS_CMP_SEL    | no -> use full line
    TST.W       (TESysJust).W                   | RTL?
    BEQ.B       TEDOTEXT_LINE_BOUNDS_CMP_SEL    | LTR -> use full line
    BSR.W       TE_LOCATE_STYLERUNS             | locate style runs in range
    SUBQ.W      #0x1,D0                         | one run only?
    BNE.B       TEDOTEXT_LINE_BOUNDS_LAST_RUN   | no -> get last run's bounds
    MOVE.W      (A2),D0                         | yes -> use line start
    MOVE.W      0x2(A2),D1                      | use line end
    BRA.B       TEDOTEXT_LINE_BOUNDS_CMP_SEL    | -> compare with sel
TEDOTEXT_LINE_BOUNDS_LAST_RUN:
    SUBQ.W      #0x1,D0                         | adjust to last index
    LSL.W       #0x2,D0                         | * 4 (entry size)
    NEG.W       D0                              | negate offset (RTL counts back)
    MOVE.W      0x0(A0,D0.W),D1                 | D1 = last run's start pos
    MOVE.W      (A2),D0                         | D0 = line start
    CMP.W       (A0),D0                         | line start before first run?
    BCC.B       TEDOTEXT_LINE_BOUNDS_CMP_SEL    | no -> use lineStart as-is
    MOVE.W      (A0),D0                         | clamp D0 to first run's start
TEDOTEXT_LINE_BOUNDS_CMP_SEL:
    CMP.W       D0,D3                           | range start at line start?
    BNE.B       TEDOTEXT_LINE_BOUNDS_NORMAL_LEFT | no -> normal teRectLeft
    MOVE.W      #0x8002,0x12(A3)                | yes -> mark "starts at line"
TEDOTEXT_LINE_BOUNDS_NORMAL_LEFT:
    CMP.W       D1,D4                           | range end at line end?
    BNE.B       TEDOTEXT_LINE_BOUNDS_RTS        | no -> normal teRectLeftSave
    MOVE.W      #0x7FFE,0x16(A3)                | yes -> mark "extends past line"
TEDOTEXT_LINE_BOUNDS_RTS:
    RTS                                         | return from TEDOTEXT_LINE_BOUNDS
| ----------------------------------------------------------
| TEDOTEXT_ADV_PAST_LINES - advance pen (teRectTop) past N lines.
| In: D0 = number of lines to advance, D1 = run height.
| Updates teRectTop, teRectLeft, A2 = lineStarts entry.
| ----------------------------------------------------------
TEDOTEXT_ADV_PAST_LINES:
    MOVE.W      0x14(A3),0x10(A3)               | teRectTop = current pen y
    BSR.W       TE_CUR_LINE_HEIGHT              | get current line height -> D1
    ADD.W       D1,0x14(A3)                     | advance pen by line height
    ADD.W       D0,D0                           | * 2 (word offset)
    LEA.L       0x60(A3,D0.W),A2                | A2 = lineStarts[D0]
    MOVE.W      0x2(A3),0x12(A3)                | teRectLeft = teViewRect.left
    BSR.W       TE_APPLY_JUST                   | apply justification
    RTS                                         | return from TEDOTEXT_ADV_PAST_LINES
| ----------------------------------------------------------
| P_TEDOTEXT_CONT_2 - get current line index from A2.
| Out: D0 = line index = (A2 - teLineStarts) / 2.
| Called by: TEHILITE_DRAW_ENTRY, TEDOTEXT_NEG_ASCENT, TEDOTEXT_LINE_DONE, TEDOTEXT_INIT_SCAN_STATE, TE_LINE_HEIGHT_AT_CHAR
| ----------------------------------------------------------
P_TEDOTEXT_CONT_2:
    LEA.L       0x60(A3),A0                     | A0 = teLineStarts base
    MOVE.L      A2,D0                           | D0 = current entry ptr
    SUB.L       A0,D0                           | D0 = byte offset
    ASR.L       #0x1,D0                         | / 2 = line index
    RTS                                         | return from P_TEDOTEXT_CONT_2
| ----------------------------------------------------------
| TEDOTEXT_INIT_SCAN_STATE - initialize text scan state for P_TEDoText loop.
| Sets teRect to teDestRect, advances teRectTop past prior
| lines (using cumulative line heights), applies justification,
| stores initial teRectLeft in local var -0x4(A6).
| ----------------------------------------------------------
TEDOTEXT_INIT_SCAN_STATE:
    BSR.B       P_TEDOTEXT_CONT_2               | D0 = current line index
    MOVE.W      D0,D1                           | D1 = same
    MOVEQ.L     #0x0,D0                         | start from line 0
    BSR.W       TE_TOTAL_HEIGHT                 | sum heights of lines 0..D1
    LEA.L       0x8(A3),A0                      | A0 = end of teViewRect (botRight+8)
    LEA.L       0x18(A3),A1                     | A1 = end of teRect+8
    MOVE.L      -(A0),-(A1)                     | copy viewRect.botRight to teRect
    MOVE.L      -(A0),-(A1)                     | copy viewRect.topLeft to teRect
    ADD.W       D0,(A1)                         | advance teRect.top by sum
    MOVE.W      (A1),0x4(A1)                    | teRect.bottom = teRect.top
    MOVE.W      D1,D0                           | D0 = current line index
    BSR.W       TE_CUR_LINE_HEIGHT              | D1 = current line height
    ADD.W       D1,0x4(A1)                      | teRect.bottom += line height
| Fall through to TE_APPLY_JUST (apply justification)
TE_APPLY_JUST:
    MOVE.W      0x3A(A3),-(A7)                  | save teJust value
    BNE.B       TE_APPLY_JUST_MEASURE           | non-zero -> apply
    MOVE.W      (TESysJust).W,(A7)              | else use system default
    BEQ.B       TE_JUST_STORE                   | left-justify -> done
TE_APPLY_JUST_MEASURE:
    BSR.W       P_TEDOTEXT_CONT_4               | measure trimmed line width -> D0
    MOVE.W      0x6(A3),D1                      | D1 = teViewRect.right
    SUB.W       0x2(A3),D1                      | D1 = view width
    SUB.W       D0,D1                           | D1 = view width - text width
    SUBQ.W      #0x1,D1                         | adjust by 1
    TST.W       (A7)                            | center justify (positive)?
    BMI.B       TE_JUST_FULL_OFFSET             | no (right) -> use full offset
    ASR.W       #0x1,D1                         | center: half offset
TE_JUST_FULL_OFFSET:
    ADD.W       D1,0x12(A3)                     | shift teRectLeft by offset
TE_JUST_STORE:
    ADDQ.W      #0x1,0x12(A3)                   | teRectLeft += 1 (caret cushion)
    MOVE.W      0x12(A3),0x16(A3)               | teRectLeftSave = teRectLeft
    MOVE.W      0x12(A3),-0x4(A6)               | save initial teRectLeft to local
    ADDQ.L      #0x2,A7                         | discard saved teJust
    RTS                                         | return from TE_APPLY_JUST
| ----------------------------------------------------------
| TE_TOTAL_HEIGHT - sum line heights for lines D0..D1-1.
| Unstyled TE: lineHeight is constant in TERec.lineHite.
| Styled TE: walks lineHeights array in StyleRec, masking
| 0x7FFF (the high bit is the line-end-with-CR flag).
| Called by: TE_RECALC_LINES, TEHILITE_DRAW_ENTRY, TEDOTEXT_INIT_SCAN_STATE, PINSCROLL_HEIGHT
| ----------------------------------------------------------
TE_TOTAL_HEIGHT:
    MOVEM.L     D1-D2,-(A7)                     | save D1-D2
    SUB.W       D0,D1                           | D1 = number of lines
    BEQ.B       TE_TOTAL_HEIGHT_SIMPLE          | zero lines -> 0
    MOVE.W      0x18(A3),D2                     | D2 = teLineHite
    BMI.B       TE_TOTAL_HEIGHT_WALK            | -1 (per-line) -> walk array
    TST.W       0x50(A3)                        | styled TE?
    BMI.B       TE_TOTAL_HEIGHT_WALK            | yes -> walk array
TE_TOTAL_HEIGHT_SIMPLE:
    MULU.W      D1,D2                           | total = lines * lineHite
    BRA.W       TE_TOTAL_HEIGHT_RTS             | -> return
TE_TOTAL_HEIGHT_WALK:
    MOVEA.L     0x4A(A3),A0                     | A0 = StyleRec handle
    MOVEA.L     (A0),A0                         | A0 = StyleRec ptr
    MOVEA.L     0x8(A0),A0                      | A0 = lineHeights handle
    MOVEA.L     (A0),A0                         | A0 = lineHeights array
    LSL.W       #0x2,D0                         | starting offset (4 bytes/entry)
    ADDA.W      D0,A0                           | A0 = lineHeights[D0]
    MOVEQ.L     #0x0,D2                         | D2 = total height
TE_TOTAL_HEIGHT_LOOP:
    MOVE.W      (A0),D0                         | D0 = entry word
    ANDI.W      #0x7FFF,D0                      | mask off CR-end bit
    ADD.W       D0,D2                           | accumulate height
    ADDQ.W      #0x4,A0                         | next entry (4 bytes)
    SUBQ.W      #0x1,D1                         | one less line
    BNE.B       TE_TOTAL_HEIGHT_LOOP            | continue
TE_TOTAL_HEIGHT_RTS:
    MOVE.L      D2,D0                           | D0 = total height
    MOVEM.L     (A7)+,D1-D2                     | restore registers
    RTS                                         | return from TE_TOTAL_HEIGHT
| ----------------------------------------------------------
| TE_CUR_LINE_HEIGHT - get height of single line at index D0.
| Out: D1 = line height (masked 0x7FFF).
| Unstyled TE: returns teLineHite.
| ----------------------------------------------------------
TE_CUR_LINE_HEIGHT:
    MOVE.W      0x18(A3),D1                     | D1 = teLineHite
    BPL.B       TE_CUR_LINE_HEIGHT_RTS          | not -1 -> use as-is
    TST.W       0x50(A3)                        | styled TE?
    BPL.B       TE_CUR_LINE_HEIGHT_RTS          | no -> keep -1 (caller error)
    MOVEA.L     0x4A(A3),A0                     | A0 = StyleRec handle
    MOVEA.L     (A0),A0                         | A0 = StyleRec ptr
    MOVEA.L     0x8(A0),A0                      | A0 = lineHeights handle
    MOVEA.L     (A0),A0                         | A0 = lineHeights array
    MOVE.W      D0,D1                           | D1 = line index
    LSL.W       #0x2,D1                         | * 4 = byte offset
    MOVE.W      0x0(A0,D1.W),D1                 | D1 = entry word
    ANDI.W      #0x7FFF,D1                      | mask off CR-end bit
TE_CUR_LINE_HEIGHT_RTS:
    RTS                                         | return from TE_CUR_LINE_HEIGHT
| ----------------------------------------------------------
| P_TEDOTEXT_CONT_4 - load char range from current lineStarts
| entry into D6/D7, then fall through into XTRIMMEASURE.
| ----------------------------------------------------------
P_TEDOTEXT_CONT_4:
    MOVE.W      (A2),D6                         | D6 = line start char
    MOVE.W      0x2(A2),D7                      | D7 = line end char
| ----------------------------------------------------------
| P_XTrimMeasure - hookable trampoline to (0x7F4) lowmem.
| Stacked-RTS tail-call to TEXTrimHook (line-trim measurer).
| ----------------------------------------------------------
P_XTrimMeasure:
    MOVE.L      (0x7F4).W,-(A7)                 | push hook proc address
    RTS                                         | tail-call to hook
| ----------------------------------------------------------
| XTRIMMEASURE - default trimmed-line measurer.
| Pascal-style: function XTrimMeasure(D6=lineStart,
| D7=lineEnd): D0 (pixels). Trims trailing spaces (chars
| <= 0x20) before measuring so that justification ignores
| trailing whitespace when computing line width.
| ----------------------------------------------------------
XTRIMMEASURE:
    CMP.W       0x3C(A3),D6                     | line starts at teLength?
    BEQ.W       XTRIMMEASURE_EMPTY              | yes -> width = 0
    CMP.W       D6,D7                           | empty line (start>=end)?
    BLS.W       XTRIMMEASURE_EMPTY              | yes -> width = 0
    MOVEA.L     0x3E(A3),A0                     | A0 = text handle
    MOVEA.L     (A0),A0                         | A0 = text ptr
XTRIMMEASURE_OK:
    SUBQ.W      #0x1,D7                         | D7 = trial trim position
    CMP.W       D6,D7                           | back to line start?
    BEQ.B       XTRIMMEASURE_OK_2               | yes -> stop trimming
    CMPI.B      #0x20,0x0(A0,D7.W)              | char[D7] is space or below?
    BLS.B       XTRIMMEASURE_OK                 | yes -> trim further
XTRIMMEASURE_OK_2:
    ADDQ.W      #0x1,D7                         | restore last non-space
| ----------------------------------------------------------
| XTRIMMEASURE_CONT - measure pixels for char range D6..D7.
| Branches by styled-flag: unstyled uses single P_Char2Pixel;
| styled walks each style run via SetPortFromStyleRun.
| ----------------------------------------------------------
XTRIMMEASURE_CONT:
    CMP.W       D6,D7                           | empty range?
    BLS.W       XTRIMMEASURE_EMPTY              | yes -> width = 0
    MOVEM.L     D2/D4/D6,-(A7)                  | save scratch registers
    .byte 0xCC,0xBA,0x05,0x0C                   | AND.L (TEPHysMask).W,D6 (mask high word)
    TST.W       0x50(A3)                        | styled TE?
    BMI.B       XTRIMMEASURE_PLAIN              | yes -> walk runs
    MOVE.W      D7,D0                           | D0 = end char
    BSR.W       XTRIMMEASURE_CHAR2PIXEL         | measure D6..D7 -> D1
    MOVE.W      D1,D0                           | D0 = total width
    BRA.B       XTRIMMEASURE_RTS                | -> exit
XTRIMMEASURE_PLAIN:
    MOVEQ.L     #0x0,D4                         | D4 = accumulated width
    MOVE.W      D6,D0                           | D0 = start char
    BSR.W       DateToSeconds                   | locate StyleRec entry
    MOVE.W      D7,D1                           | D1 = end char
    BSR.W       CountRunsBefore                 | count runs in range
    MOVE.W      D0,D2                           | D2 = run count
XTRIMMEASURE_RUN_LOOP:
    BSR.W       SetPortFromStyleRun             | apply run's font/style
    ADDQ.W      #0x4,A0                         | step to next run header
    MOVE.W      (A0),D0                         | D0 = next run start
    CMP.W       D0,D7                           | range ends in this run?
    BCC.B       XTRIMMEASURE_CLAMP_END          | no -> measure to next-run-start
    MOVE.W      D7,D0                           | yes -> measure to D7
XTRIMMEASURE_CLAMP_END:
    MOVE.W      D2,-(A7)                        | save run count
    BSR.W       XTRIMMEASURE_CHAR2PIXEL         | measure D6..D0 -> D1
    ADD.W       D1,D4                           | accumulate width
    MOVE.W      (A7)+,D2                        | restore run count
    MOVE.W      (A0),D6                         | D6 = next run's start (new D6)
    SUBQ.W      #0x1,D2                         | one less run
    BNE.B       XTRIMMEASURE_RUN_LOOP           | more runs -> continue
    MOVE.W      D4,D0                           | D0 = total width
XTRIMMEASURE_RTS:
    MOVEM.L     (A7)+,D2/D4/D6                  | restore registers
    RTS                                         | return from XTRIMMEASURE
XTRIMMEASURE_EMPTY:
    MOVEQ.L     #0x0,D0                         | width = 0
    RTS                                         | return from XTRIMMEASURE
| ----------------------------------------------------------
| XTRIMMEASURE_CHAR2PIXEL - call P_Char2Pixel for char range D6..D0.
| Out: D1 = pixel width.
| ----------------------------------------------------------
XTRIMMEASURE_CHAR2PIXEL:
    MOVE.L      A0,-(A7)                        | save A0
    MOVEA.L     0x3E(A3),A0                     | A0 = text handle
    MOVEA.L     (A0),A0                         | A0 = text ptr
    MOVE.W      D6,D1                           | D1 = start char
    SUB.W       D1,D0                           | D0 = char count (end-start)
    MOVEQ.L     #0x0,D2                         | D2 = 0 (initialize)
    BSR.W       P_Char2Pixel                    | invoke hook proc
    MOVEA.L     (A7)+,A0                        | restore A0
    RTS                                         | return from XTRIMMEASURE_CHAR2PIXEL
| ----------------------------------------------------------
| P_Char2Pixel - hookable trampoline to (0x79C) lowmem.
| Stacked-RTS tail-call to char-to-pixel hook.
| ----------------------------------------------------------
P_Char2Pixel:
    MOVE.L      (0x79C).W,-(A7)                 | push hook proc address
    RTS                                         | tail-call to hook
| ----------------------------------------------------------
| VCHAR2PIXEL - default char-to-pixel converter.
| In: D0 = char count, D1 = start offset, A0 = text ptr.
| Out: D1 = pixel width, via _TextWidth trap.
| ----------------------------------------------------------
VCHAR2PIXEL:
    SUBQ.W      #0x2,A7                         | room for _TextWidth result
    MOVE.L      A0,-(A7)                        | push text ptr
    MOVE.W      D1,-(A7)                        | push offset
    MOVE.W      D0,-(A7)                        | push count
    _TextWidth                                  | measure -> stack
    MOVE.W      (A7)+,D1                        | D1 = pixel width
    RTS                                         | return from VCHAR2PIXEL
| ----------------------------------------------------------
| TEDOTEXT_REPOS_PEN - reposition pen for line drawing.
| Computes pen position based on selStart/selEnd char range
| within the current line, then _MoveTo's there. Used at the
| start of each line during P_TEDoText draw operations.
| ----------------------------------------------------------
TEDOTEXT_REPOS_PEN:
    CMP.W       (A2),D3                         | sel range starts after line?
    BHI.B       TEDOTEXT_REPOS_RANGE            | yes -> measure both ends
    CMP.W       0x2(A2),D4                      | sel range ends before line end?
    BCS.B       TEDOTEXT_REPOS_RANGE            | yes -> measure both ends
    MOVE.W      D4,D7                           | D7 = line end
    BSR.W       XTRIMMEASURE_CONT               | measure line end pixels
    ADD.W       D0,0x16(A3)                     | extend teRectLeftSave
    BRA.B       TEDOTEXT_REPOS_MOVETO           | -> _MoveTo
TEDOTEXT_REPOS_RANGE:
    MOVE.W      D3,D7                           | D7 = sel start
    BSR.W       TE_MEASURE_RANGE                | measure to sel start
    ADD.W       D0,0x12(A3)                     | extend teRectLeft
    MOVE.W      D4,D7                           | D7 = sel end
    BSR.W       TE_MEASURE_RANGE                | measure to sel end
    ADD.W       D0,0x16(A3)                     | extend teRectLeftSave
TEDOTEXT_REPOS_MOVETO:
    LEA.L       0x10(A3),A1                     | A1 = teRect (= teLine baseline)
    MOVE.W      0x2(A1),-0x2(A6)                | save teRect.left to local
    MOVE.W      0x2(A1),(scratch8).W            | save to scratch (callback safety)
    MOVE.L      0x4(A1),-(A7)                   | push teRect.right+top word
    _MoveTo                                     | move pen to baseline
    RTS                                         | return from TEDOTEXT_REPOS_PEN
| ----------------------------------------------------------
| TE_MEASURE_RANGE - measure pixels for partial char range D6..D7.
| D6 = current line start, D7 = char position to measure to.
| For unstyled or LTR styled: walks chars via XTRIMMEASURE_CONT.
| For RTL styled: walks style runs in reverse.
| Out: D0 = pixel offset within line.
| ----------------------------------------------------------
TE_MEASURE_RANGE:
    MOVEM.L     D3/D5-D6,-(A7)                  | save scratch
    MOVEQ.L     #0x0,D5                         | D5 = accumulated pixels
    MOVE.W      (A2),D6                         | D6 = line start char
    CMP.W       D6,D7                           | D7 < line start?
    BCS.B       TE_MEASURE_RTS                  | yes -> 0
    TST.W       0x50(A3)                        | styled TE?
    BPL.B       TE_MEASURE_LAST_RUN             | no -> simple measure
    TST.W       (TESysJust).W                   | RTL?
    BEQ.B       TE_MEASURE_LAST_RUN             | LTR -> simple measure
    MOVE.W      D6,D3                           | D3 = line start
    MOVE.W      (A2),D0                         | D0 = line start
    MOVE.W      0x2(A2),D1                      | D1 = line end
    BSR.W       TE_LOCATE_STYLERUNS             | locate runs in line range
    MOVE.W      D7,D0                           | D0 = target char
TE_MEASURE_RANGE_LOOP:
    MOVE.W      (A0),D6                         | D6 = run start
    CMP.W       D6,D3                           | run start < line start?
    BLS.B       TE_MEASURE_USE_RUN_START        | no -> use run start
    MOVE.W      D3,D6                           | clamp to line start
TE_MEASURE_USE_RUN_START:
    CMP.W       D6,D7                           | target before run start?
    BCS.B       TE_MEASURE_CLAMP_RUN_END        | yes -> measure run partially
    MOVE.W      D7,D0                           | D0 = target
    CMP.W       0x4(A0),D7                      | target past run end?
    BLS.B       TE_MEASURE_LAST_RUN             | no -> last run, do simple
TE_MEASURE_CLAMP_RUN_END:
    MOVE.W      0x4(A0),D0                      | D0 = run end
    CMP.W       0x2(A2),D0                      | past line end?
    BLS.B       TE_MEASURE_RUN                  | no -> use run end
    MOVE.W      0x2(A2),D0                      | clamp to line end
TE_MEASURE_RUN:
    MOVE.W      D0,-(A7)                        | save measure end
    BSR.W       SetPortFromStyleRun             | apply run's font
    MOVE.W      (A7)+,D0                        | restore measure end
    BSR.W       XTRIMMEASURE_CHAR2PIXEL         | measure D6..D0
    ADD.W       D1,D5                           | accumulate pixels
    SUBQ.L      #0x4,A0                         | RTL: previous run
    BRA.B       TE_MEASURE_RANGE_LOOP           | continue
TE_MEASURE_LAST_RUN:
    BSR.W       XTRIMMEASURE_CONT               | measure D6..D7
    ADD.W       D0,D5                           | accumulate pixels
TE_MEASURE_RTS:
    MOVE.W      D5,D0                           | D0 = total pixels
    MOVEM.L     (A7)+,D3/D5-D6                  | restore scratch
    RTS                                         | return from TE_MEASURE_RANGE
| ----------------------------------------------------------
| XTRIMMEASURE_CONT_3 - clamp char range D3..D4 to viewable lines.
| Translates the y coords of teRect's top and bottom into
| line indices via TE_PIXELY_TO_LINE, then clamps D3 (selStart) and
| D4 (selEnd) to the corresponding lineStarts so we don't
| process invisible lines.
| ----------------------------------------------------------
XTRIMMEASURE_CONT_3:
    LEA.L       0x8(A3),A0                      | A0 = teViewRect ptr
XTRIMMEASURE_CONT_4:
    MOVE.W      (A0),D0                         | D0 = viewRect.top
    BSR.B       TE_PIXELY_TO_LINE               | y-coord -> line index
    BGE.B       XTRIMMEASURE_CONT_5             | line not visible -> empty
    ADD.W       D0,D0                           | * 2 (word offset)
    BLT.B       TE_VIEWRECT_BOTTOM_OK           | invalid -> bottom only
    CMP.W       0x60(A3,D0.W),D3                | D3 < lineStart[top]?
    BCC.B       XTRIMMEASURE_NO_3               | no -> keep D3
    MOVE.W      0x60(A3,D0.W),D3                | clamp D3 to top
XTRIMMEASURE_NO_3:
    CMP.W       0x60(A3,D0.W),D4                | D4 < lineStart[top]?
    BCC.B       TE_VIEWRECT_BOTTOM_OK           | no -> keep D4
    MOVE.W      0x60(A3,D0.W),D4                | clamp D4 to top
TE_VIEWRECT_BOTTOM_OK:
    MOVE.W      0x4(A0),D0                      | D0 = viewRect.bottom
    SUBQ.W      #0x1,D0                         | inclusive bottom
    BSR.B       TE_PIXELY_TO_LINE               | y-coord -> line index
    ADDQ.W      #0x1,D0                         | exclusive line index
    CMP.W       0x5E(A3),D0                     | past nLines?
    BHI.B       XTRIMMEASURE_DONE               | yes -> done
    ADD.W       D0,D0                           | * 2
    CMP.W       0x60(A3,D0.W),D3                | D3 > lineStart[bottom]?
    BCS.B       XTRIMMEASURE_NO_4               | no -> keep D3
    MOVE.W      0x60(A3,D0.W),D3                | clamp D3 to bottom
XTRIMMEASURE_NO_4:
    CMP.W       0x60(A3,D0.W),D4                | D4 > lineStart[bottom]?
    BCS.B       XTRIMMEASURE_DONE               | no -> keep D4
    MOVE.W      0x60(A3,D0.W),D4                | clamp D4 to bottom
XTRIMMEASURE_DONE:
    RTS                                         | return from XTRIMMEASURE_CONT_3
XTRIMMEASURE_CONT_5:
    MOVE.W      D3,D4                           | empty range -> D4 = D3
    RTS                                         | return from XTRIMMEASURE_CONT_3
| ----------------------------------------------------------
| TE_PIXELY_TO_LINE - convert y-coord to line index.
| In: D0 = absolute y-coord (port-relative).
| Out: D0 = line index, D1 set negative if before, GE if past.
| Unstyled TE: divides by lineHite. Styled TE: walks
| lineHeights array and accumulates until y is reached.
| ----------------------------------------------------------
TE_PIXELY_TO_LINE:
    MOVEM.L     D2/D6-D7/A0,-(A7)               | save scratch
    SUB.W       (A3),D0                         | D0 = y - destRect.top
    EXT.L       D0                              | sign-extend
    MOVE.W      0x5E(A3),D7                     | D7 = nLines
    BEQ.B       TE_PIXELY_RTS                   | empty TE -> D0=0
    MOVE.W      0x18(A3),D1                     | D1 = lineHite
    TST.W       0x50(A3)                        | styled TE?
    BPL.B       TE_PIXELY_SIMPLE_DIV            | no -> simple divide
    TST.W       D1                              | lineHite == -1?
    BMI.B       TE_PIXELY_WALK_HEIGHTS          | yes -> walk lineHeights
TE_PIXELY_SIMPLE_DIV:
    DIVS.W      D1,D0                           | line index = y / lineHite
    BRA.B       TE_PIXELY_RTS                   | -> exit
TE_PIXELY_WALK_HEIGHTS:
    MOVEA.L     0x4A(A3),A0                     | A0 = StyleRec handle
    MOVEA.L     (A0),A0                         | A0 = StyleRec ptr
    MOVEA.L     0x8(A0),A0                      | A0 = lineHeights handle
    MOVEA.L     (A0),A0                         | A0 = lineHeights array
    MOVEQ.L     #0x0,D1                         | D1 = cumulative height
    MOVE.W      D7,D2                           | D2 = countdown nLines
TE_PIXELY_WALK_LOOP:
    MOVE.W      (A0),D6                         | D6 = entry word
    ANDI.W      #0x7FFF,D6                      | mask off CR-end bit
    ADD.W       D6,D1                           | accumulate height
    ADDQ.W      #0x4,A0                         | next entry (4 bytes)
    CMP.W       D1,D0                           | y < cumulative?
    BLT.B       TE_PIXELY_FOUND_LINE            | yes -> found line
    SUBQ.W      #0x1,D2                         | next line
    BNE.B       TE_PIXELY_WALK_LOOP             | continue
TE_PIXELY_FOUND_LINE:
    MOVE.W      D7,D0                           | D0 = nLines - countdown
    SUB.W       D2,D0                           | = current line index
TE_PIXELY_RTS:
    CMP.W       D7,D0                           | set CCR (D0 vs nLines)
    MOVEM.L     (A7)+,D2/D6-D7/A0               | restore scratch
    RTS                                         | return from TE_PIXELY_TO_LINE
| ----------------------------------------------------------
| XTRIMMEASURE_CONT_7 - invoke teHiliteHook (or default _InvertRect).
| In: D0 = hook proc address (0 = default), 0x10(A3) = teLine.
| If D0 nonzero, jumps to hook; else falls through to invert.
| ----------------------------------------------------------
XTRIMMEASURE_CONT_7:
    PEA.L       0x10(A3)                        | push teLine rect
    BEQ.B       XTRIMMEASURE_NO_5               | D0 == 0 -> default
    MOVEA.L     D0,A0                           | A0 = hook proc
    JMP         (A0)                            | tail-call hook
XTRIMMEASURE_NO_5:
    _InvertRect                                 | invert teLine rect
    RTS                                         | return from XTRIMMEASURE_CONT_7
| ----------------------------------------------------------
| TE_PROLOGUE_NODISP - universal _TE prologue (non-dispatched).
| Called by all standard _TE traps with TEHandle as param.
| Sets up A6 frame, locks TERec and text handle, saves port,
| clips to teViewRect, applies TERec font/face/mode/size,
| reads teLength from text handle, clamps selStart/selEnd.
| Locals: -0x2 = TERec lock state, -0x6 = saved port,
|         -0xA = saved clip rgn, -0xC = text handle lock,
|         -0xE = txFont, -0x10 = txFace, -0x12 = txSize,
|         -0x18 = scratch for BuildHilitePattern.
| Called by: TEGETTEXT, TESETTEXT, TECALTEXT, TESETSELECT, TEUPDATE (and 16 more)
| ----------------------------------------------------------
TE_PROLOGUE_NODISP:
    MOVEQ.L     #0x0,D0                         | D0 = 0 (no dispatch indirection)
TE_PROLOGUE_BODY:
    MOVEA.L     (A7)+,A0                        | A0 = saved return address
    LINK        A6,#-0x18                       | 24 bytes locals
    MOVEM.L     D2-D7/A2-A4,-(A7)               | save scratch registers
    MOVE.L      A0,-(A7)                        | restore return addr on stack
    TST.W       D0                              | dispatched call?
    BEQ.B       TE_PROLOGUE_NO_DISPATCH         | no -> use 0x8(A6) as TEHandle
    MOVE.W      0x8(A6),D0                      | D0 = dispatch selector
    LEA.L       TEXTEDIT(PC),A0                 | A0 = TEDispatch table base
    ADD.W       D0,D0                           | * 2 (word entries)
    MOVE.W      0x0(A0,D0.W),D0                 | D0 = entry offset
    LEA.L       0x0(A0,D0.W),A0                 | A0 = handler proc
    MOVE.L      A0,D3                           | D3 = handler addr (TEDispatch)
    MOVEA.L     0xA(A6),A4                      | A4 = TEHandle (after selector)
    BRA.B       TE_PROLOGUE_COMMON              | -> common setup
TE_PROLOGUE_NO_DISPATCH:
    MOVEQ.L     #0x0,D3                         | D3 = 0 (no dispatch handler)
    MOVEA.L     0x8(A6),A4                      | A4 = TEHandle param
TE_PROLOGUE_COMMON:
    MOVEA.L     A4,A0                           | A0 = TEHandle
    _HGetState                                  | get current lock state
    MOVE.B      D0,-0x2(A6)                     | save lock state
    PEA.L       -0x6(A6)                        | push ptr for saved port
    _GetPort                                    | save current port
    MOVEA.L     A4,A0                           | A0 = TEHandle
    _HLock                                      | lock TERec
    MOVEA.L     (A4),A3                         | A3 = TERec ptr
    MOVEA.L     0x52(A3),A2                     | A2 = teGrafPort
    MOVE.L      A2,-(A7)                        | push GrafPort
    _SetPort                                    | install TE's GrafPort
    SUBQ.W      #0x4,A7                         | room for new rgn
    _NewRgn                                     | allocate scratch region
    MOVE.L      (A7),-0xA(A6)                   | save scratch region handle
    MOVE.L      (A7),-(A7)                      | re-push for _GetClip
    _GetClip                                    | save current clip into scratch
    PEA.L       0x8(A3)                         | push teViewRect
    _ClipRect                                   | clip drawing to viewRect
    MOVE.L      0x1C(A2),-(A7)                  | push port.visRgn
    MOVE.L      (A7),-(A7)                      | push scratch (dst = visRgn intersect)
    _SectRgn                                    | clip = clip intersect visRgn
    MOVEA.L     0x52(A3),A0                     | A0 = teGrafPort
    TST.W       0x50(A3)                        | styled TE?
    BMI.B       TE_PROLOGUE_PORT_STYLED         | yes -> port already has style
    MOVE.L      0x4A(A3),0x44(A0)               | port.txFont/Face = TERec
    MOVE.L      0x4E(A3),0x48(A0)               | port.txMode/Size = TERec
TE_PROLOGUE_PORT_STYLED:
    MOVE.W      0x44(A0),-0xE(A6)               | save txFont
    MOVE.W      0x46(A0),-0x10(A6)              | save txFace
    MOVE.W      0x4A(A0),-0x12(A6)              | save txSize
    PEA.L       -0x18(A6)                       | push scratch buffer
    BSR.W       BuildHilitePattern              | initialize text-measure ctx
    MOVEA.L     0x3E(A3),A0                     | A0 = text handle
    _HGetState                                  | get text handle lock state
    MOVE.B      D0,-0xC(A6)                     | save text lock state
    _HLock                                      | lock text handle
    _GetHandleSize                              | D0 = text length
    MOVE.W      D0,0x3C(A3)                     | teLength = text length
| XTRIMMEASURE_CONT_14 -- clamp selection to text length.
XTRIMMEASURE_CONT_14:
    MOVE.W      0x3C(A3),D0                     | D0 = teLength
    MOVE.W      0x22(A3),D1                     | D1 = teSelEnd
    SUB.W       D0,D1                           | D1 = selEnd - teLength
    BLS.B       XTRIMMEASURE_OK_4               | selEnd <= teLength -> ok
    MOVE.W      D0,0x22(A3)                     | clamp teSelEnd to teLength
XTRIMMEASURE_OK_4:
    MOVE.W      0x20(A3),D1                     | D1 = teSelStart
    SUB.W       0x22(A3),D1                     | D1 = selStart - selEnd
    BLS.B       TE_PROLOGUE_SEL_OK              | selStart <= selEnd -> ok
    SUB.W       D1,0x20(A3)                     | clamp teSelStart to selEnd
TE_PROLOGUE_SEL_OK:
    BSR.B       XTRIMMEASURE_CONT_15            | order selStart/selEnd
    TST.L       D3                              | dispatched call?
    BEQ.B       TE_PROLOGUE_DISPATCHED          | no -> A2 = first param
    MOVEA.L     D3,A0                           | A0 = handler proc
    LEA.L       0xE(A6),A2                      | A2 = first param (after selector)
    BRA.B       TE_PROLOGUE_RTS                 | -> return
TE_PROLOGUE_DISPATCHED:
    LEA.L       0xC(A6),A2                      | A2 = first param (no selector)
TE_PROLOGUE_RTS:
    RTS                                         | return from TE_PROLOGUE_NODISP
| ----------------------------------------------------------
| TEDISPATCH ($A83D) - styled-TE dispatch trap.
| Pascal: procedure TEDispatch(selector: INTEGER; ...);
| Calls TE_PROLOGUE_BODY with D0=1 to take dispatch table indirection,
| then jumps to the handler returned in A0.
| ----------------------------------------------------------
TEDISPATCH:
    MOVEQ.L     #0x1,D0                         | D0 = 1 (dispatch via selector)
    BSR.W       TE_PROLOGUE_BODY                | common prologue, A0 = handler
    JMP         (A0)                            | tail-call dispatched handler
| ----------------------------------------------------------
| XTRIMMEASURE_CONT_15 - order teSelStart and teSelEnd.
| Loads as long-word, swaps if start > end. Out: A2 -> teSelStart.
| Called during boot (2,779 times in 30s trace).
| ----------------------------------------------------------
XTRIMMEASURE_CONT_15:
    LEA.L       0x20(A3),A2                     | A2 -> teSelStart/teSelEnd pair
    MOVE.L      (A2),D0                         | D0.H=teSelStart, D0.L=teSelEnd
    CMP.W       (A2),D0                         | D0.L vs D0.H (selEnd vs selStart)
    BCC.B       TE_ORDER_SEL_RTS                | selEnd >= selStart -> ok
    SWAP.W      D0                              | swap fields
    MOVE.L      D0,(A2)                         | store swapped pair
TE_ORDER_SEL_RTS:
    RTS                                         | return from XTRIMMEASURE_CONT_15
| ----------------------------------------------------------
| _TECopy ($A9D5) - copy selection to TextEdit scrap.
| Pascal: procedure TECopy(hTE: TEHandle);
| Copies teSelStart..teSelEnd bytes into TEScrpHandle, then
| (for styled TE) writes 'styl' resource to system scrap and
| 'TEXT' for the text. Unstyled TE only updates TEScrpHandle.
| ----------------------------------------------------------
TECOPY:
    BSR.W       TE_PROLOGUE_NODISP              | _TE prologue
    BSR.B       XTRIMMEASURE_CONT_15            | order selection
    SUB.W       (A2),D0                         | D0 = selLen = selEnd - selStart
    MOVE.W      D0,(TEScrpLength).W             | TEScrpLength = selLen
    MOVEA.L     0x3E(A3),A0                     | A0 = text handle
    MOVEA.L     (A0),A0                         | A0 = text ptr
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.W      (A2),D0                         | D0 = teSelStart
    ADDA.L      D0,A0                           | A0 = text + selStart
    MOVEA.L     (TEScrpHandle).W,A1             | A1 = TEScrpHandle
    MOVE.W      (TEScrpLength).W,D0             | D0 = bytes to copy
    _PtrToXHand                                 | extend handle and copy
    TST.W       0x50(A3)                        | styled TE?
    BPL.B       TECOPY_PUTSCRAP_DONE            | no -> done
    SUBQ.W      #0x4,A7                         | room for _ZeroScrap result
    _ZeroScrap                                  | clear system scrap
    ADDQ.L      #0x4,A7                         | discard result
    BSR.B       XTRIMMEASURE_CONT_15            | re-order (after handle move)
    BSR.W       TE_PUT_STYL_SCRAP               | put 'styl' to scrap
    MOVEA.L     0x3E(A3),A0                     | A0 = text handle
    MOVEA.L     (A0),A0                         | A0 = text ptr
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.W      (A2),D0                         | D0 = teSelStart
    ADDA.W      D0,A0                           | A0 = text + selStart
    SUBQ.W      #0x4,A7                         | room for _PutScrap result
    MOVE.W      (TEScrpLength).W,D0             | D0 = byte count
    MOVE.L      D0,-(A7)                        | push length
    MOVE.L      #0x54455854,-(A7)               | push 'TEXT' type
    MOVE.L      A0,-(A7)                        | push data ptr
    _PutScrap                                   | write 'TEXT' to system scrap
    ADDQ.L      #0x4,A7                         | discard result
TECOPY_PUTSCRAP_DONE:
    BRA.W       TECALTEXT_EXIT                  | -> _TE epilogue
| ----------------------------------------------------------
| TE_PUT_STYL_SCRAP - write 'styl' resource for selection to scrap.
| In: D0 = packed (selStart, selEnd).
| Builds a styl record (header word + 20-byte StScrpRec
| entries per style run in selection range), calls _PutScrap
| with type 'styl' (0x7374796C). Used by _TECopy/_TECut.
| ----------------------------------------------------------
TE_PUT_STYL_SCRAP:
    MOVEM.L     D0/D2-D5/A2/A5,-(A7)            | save scratch
    MOVE.W      D0,D1                           | D1 = selEnd
    SWAP.W      D0                              | D0.W = selStart
    CMP.W       D0,D1                           | empty selection?
    BEQ.B       TECOPY_DISPOSE_TEMP             | yes -> done
    MOVE.W      D0,D5                           | D5 = selStart
    BSR.W       DateToSeconds                   | locate StyleRec entries
    BSR.W       CountRunsBefore                 | count runs in selection
    MOVE.W      D0,D2                           | D2 = run count
    MULU.W      #0x14,D0                        | total = runs * 20 bytes
    ADDQ.L      #0x2,D0                         | + 2 byte header (run count)
    MOVE.L      D0,D4                           | D4 = scrap size
    BSR.W       TE_RESIZE_AND_DEREF             | allocate scrap handle
    MOVEA.L     A0,A4                           | A4 = scrap handle
    MOVEA.L     (A0),A0                         | A0 = scrap data
    MOVE.W      D2,(A0)                         | header: run count
    LEA.L       0x2(A0),A1                      | A1 = first entry slot
    MOVE.W      D5,D0                           | D0 = selStart
    BSR.W       DateToSeconds                   | locate first run
    MOVEA.L     A0,A2                           | A2 = first run ptr
TECOPY_FIRST_RUN:
    ADDQ.L      #0x4,A1                         | A1 += 4 (skip charPos field)
    MOVE.W      0x2(A2),D0                      | D0 = run's font index
    BSR.W       GetStyleEntry                   | resolve to StScrpRec
    ADDQ.L      #0x2,A0                         | skip font field in source
    MOVEQ.L     #0x10,D0                        | 16 bytes (size/face/color/etc)
    _BlockMove                                  | copy style data
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.W      (A2),D0                         | D0 = run's char position
    SUB.W       D5,D0                           | D0 = relative to selStart
    BCC.B       TECOPY_CLAMP_ZERO               | not negative -> use as-is
    MOVEQ.L     #0x0,D0                         | clamp to 0
TECOPY_CLAMP_ZERO:
    MOVE.L      D0,-(A1)                        | store relative charPos
    ADDA.W      #0x14,A1                        | step to next entry slot
    ADDQ.L      #0x4,A2                         | next source run
    SUBQ.W      #0x1,D2                         | one less run
    BNE.B       TECOPY_FIRST_RUN                | continue
    SUBQ.L      #0x4,A7                         | room for _PutScrap result
    MOVE.L      D4,-(A7)                        | push length
    MOVE.L      #0x7374796C,-(A7)               | push 'styl' type
    MOVE.L      (A4),-(A7)                      | push data ptr
    _PutScrap                                   | write 'styl' to system scrap
    ADDQ.L      #0x4,A7                         | discard result
    MOVEA.L     A4,A0                           | A0 = scrap handle
    _DisposeHandle                              | free temp handle
TECOPY_DISPOSE_TEMP:
    MOVEM.L     (A7)+,D0/D2-D5/A2/A5            | restore scratch
    RTS                                         | return from TE_PUT_STYL_SCRAP
| ----------------------------------------------------------
| _TECut ($A9D6) - copy selection then delete.
| Implementation: _TECopy followed by _TEDelete.
| ----------------------------------------------------------
TECUT:
    BSR.W       TE_PROLOGUE_NODISP              | _TE prologue
    MOVE.L      A4,-(A7)                        | push TEHandle
    _TECopy                                     | copy selection to scrap
    MOVE.L      A4,-(A7)                        | push TEHandle
    _TEDelete                                   | delete selection
    BRA.W       TECOPY_PUTSCRAP_DONE            | -> _TE epilogue
| ----------------------------------------------------------
| _TEDelete ($A9D7) - delete selection range.
| Pascal: procedure TEDelete(hTE: TEHandle);
| Hides caret, removes chars from text via _Munger, recalcs
| line breaks, repositions caret, scrolls into view.
| ----------------------------------------------------------
TEDELETE:
    BSR.W       TE_PROLOGUE_NODISP              | _TE prologue
    BSR.W       TE_CARET_ERASE                  | hide caret
    BSR.B       TE_DELETE_SEL                   | delete bytes from text
    BSR.W       TE_RECALC_LINES                 | recalc lines after delete
    BSR.W       TE_CARET_RESTORE                | restore caret state
    BSR.W       SelView                         | scroll selection into view
    BRA.W       TECOPY_PUTSCRAP_DONE            | -> _TE epilogue
| ----------------------------------------------------------
| TE_DELETE_SEL - remove selection bytes from text handle.
| Updates text via _Munger (search-and-replace with 0-byte
| replacement), shrinks teLength, sets selEnd = selStart.
| For styled TE: also collapses style runs (TE_DELETE_STYLES).
| ----------------------------------------------------------
TE_DELETE_SEL:
    BSR.W       XTRIMMEASURE_CONT_15            | order selection
    MOVE.W      D0,D7                           | D7 = selEnd
    SUB.W       (A2),D7                         | D7 = selLen
    BEQ.B       TE_DELETE_SEL_RTS               | empty -> nothing to delete
    MOVE.W      D0,D1                           | D1 = selEnd
    SWAP.W      D0                              | D0.W = selStart
    BSR.W       TE_DELETE_STYLES                | collapse styles in range
    BSR.W       TEPASTE_CONT_2                  | shrink lineHeights for styled
    MOVE.W      D7,-(A7)                        | push selLen (delete count)
    CLR.W       -(A7)                           | push 0 (no replace bytes)
    CLR.L       -(A7)                           | push nil insert ptr
    CLR.L       -(A7)                           | push nil match-string ptr
    _Munger                                     | delete bytes at selStart
    ADDQ.L      #0x4,A7                         | discard result
    SUB.W       D7,0x3C(A3)                     | teLength -= selLen
    MOVE.W      (A2)+,(A2)                      | teSelEnd = teSelStart
TE_DELETE_SEL_RTS:
    RTS                                         | return from TE_DELETE_SEL
| ----------------------------------------------------------
|
| TE_DELETE_STYLES -- collapse styleRun runs that fall in the deleted
| selection range [D0, D1).
|
| Used by TEDELETE for styled TextEdit (teStyleRec set, high bit
| of teJust+1).  Walks the styleRun array and removes any runs
| entirely inside [D0,D1), shrinking the array via _BlockMove.
| For partial overlaps, adjusts the start offset of the first
| surviving run.
|
TE_DELETE_STYLES:
    MOVEM.L     D0/D2-D6/A2,-(A7)               | save regs
    TST.W       0x50(A3)                        | teStyleRec set ?
    BPL.B       TE_DELETE_RTS                   | no, not styled, return
    MOVE.W      D0,D5                           | D5 = selEnd
    SUB.W       D1,D5                           | D5 = selLen
    BEQ.B       TE_DELETE_RTS                   | empty, return
    MOVE.W      D0,D3                           | D3 = selEnd
    SUBQ.W      #0x1,D0                         | D0 = selEnd - 1
    BSR.W       DateToSeconds                   | A0 -> first run >= selStart, D0 = run #
    MOVEA.L     A0,A2                           | A2 = first affected run
    MOVE.W      D0,D6                           | D6 = first run index
    ADDQ.W      #0x1,D1                         | D1 = selStart + 1
    BSR.W       CountRunsBefore                 | D0 = run # past selEnd
    SUBQ.W      #0x1,D0                         | adjust to last affected
    MOVE.W      D0,D2                           | D2 = run count to remove
    ADD.W       D6,D0                           | D0 = end run index
    MOVE.W      D0,D6                           | D6 = end run index
    MOVEQ.L     #0x0,D4                         | clear D4
    MOVE.W      D2,D4                           | D4 = run count
    LSL.L       #0x2,D4                         | * 4 bytes per run
    ADDA.L      D4,A0                           | A0 -> first surviving run
    TST.W       D2                              | any runs to remove ?
    BNE.B       TE_DELETE_ADJ_FIRST_RUN         | yes, do it
    BSR.W       AdjustRunPositions              | no, just unref styles
    BRA.B       TE_DELETE_RTS                   | return
TE_DELETE_ADJ_FIRST_RUN:
    MOVE.W      D3,(A0)                         | adjust first surviving run.start
    BSR.W       AdjustRunPositions              | unref removed style entries
    CMP.W       (A2),D3                         | first run still has same start ?
    BEQ.B       TE_DELETE_REDUCE_COMPACT        | yes, no boundary fix needed
    ADDQ.L      #0x4,A2                         | skip first run (boundary)
    SUBQ.W      #0x4,D4                         | reduce removal count
    SUBQ.W      #0x1,D2                         | reduce run count
    BEQ.B       TE_DELETE_RTS                   | nothing left, return
TE_DELETE_REDUCE_COMPACT:
    MOVEA.L     A2,A0                           | A0 = first run to compact
    MOVE.W      D2,D0                           | D0 = remove count
    BSR.W       TE_ADJ_RUNS_AFTER_DEL           | dec follow runs' start by selLen
    MOVEA.L     0x4A(A3),A0                     | A0 = styleRecord handle
    MOVEA.L     (A0),A0                         | deref to header
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.W      (A0),D0                         | D0 = nRuns
    ADDQ.W      #0x1,D0                         | + 1 (terminator)
    SUB.W       D6,D0                           | D0 = runs after removed range
    LSL.L       #0x2,D0                         | * 4 bytes
    SUB.W       D2,(A0)                         | nRuns -= removed count
    MOVEA.L     A2,A1                           | A1 = dst (compact target)
    MOVEA.L     A2,A0                           | A0 = src (after removed)
    ADDA.L      D4,A0                           | A0 += removed bytes
    _BlockMove                                  | shift surviving runs down
TE_DELETE_RTS:
    MOVEM.L     (A7)+,D0/D2-D6/A2               | restore regs
    RTS                                         | return from TE_DELETE_STYLES
| ----------------------------------------------------------
|
| TE_ADJ_RUNS_AFTER_DEL -- decrement follow-run start offsets by selLen
|
| After deleting selLen bytes, runs after the affected range
| need their start offsets adjusted downward by selLen. Skips
| runs whose start is 0.
|
TE_ADJ_RUNS_AFTER_DEL:
    MOVEA.L     A0,A1                           | A1 = run array cursor
    MOVE.W      D0,D1                           | D1 = run count to walk
TE_ADJ_RUNS_LOOP:
    MOVE.W      0x2(A1),D0                      | D0 = run.charsToShift (?)
    BSR.W       GetStyleEntry                   | helper: locate affected run
    TST.W       (A0)                            | run.start == 0 ?
    BEQ.B       TE_ADJ_RUNS_NEXT                | yes, skip (no shift)
    SUBQ.W      #0x1,(A0)                       | run.start -= 1
TE_ADJ_RUNS_NEXT:
    ADDQ.L      #0x4,A1                         | next run
    SUBQ.W      #0x1,D1                         | dec counter
    BNE.B       TE_ADJ_RUNS_LOOP                | loop
    RTS                                         | return from TE_ADJ_RUNS_AFTER_DEL
| ----------------------------------------------------------
| TE_RECALC_LINES - recalculate line breaks after text change.
| Saves total height before recalc, calls P_doTERecal, then
| computes new total height; if shrunk, erases the now-empty
| portion of teRect and redraws via P_doTEDoText.
| Called by: TEDELETE, TE_DO_PASTE_EDIT, TEINSERT, TESetStyle_Redraw, TEReplaceStyle_Redraw
| ----------------------------------------------------------
TE_RECALC_LINES:
    MOVEQ.L     #0x0,D0                         | start = line 0
    MOVE.W      0x5E(A3),D1                     | end = nLines
    BSR.W       TE_TOTAL_HEIGHT                 | D0 = total height (pre-edit)
    MOVE.W      D0,-(A7)                        | save pre-edit height
    BSR.W       P_doTERecal                     | rebuild lineStarts
    MOVE.W      D2,D3                           | save resulting line count
    MOVEQ.L     #0x0,D0                         | start = line 0
    MOVE.W      0x5E(A3),D1                     | end = new nLines
    BSR.W       TE_TOTAL_HEIGHT                 | D0 = total height (post-edit)
    MOVE.W      (A7)+,D1                        | D1 = pre-edit height
    CMP.W       D0,D1                           | shrunk?
    BCS.B       TE_RECALC_LINES_REDRAW          | not shrunk -> redraw only
    LEA.L       0x10(A3),A0                     | A0 = teLine rect
    ADD.W       (A3),D1                         | D1 = old bottom (port y)
    MOVE.W      D1,0x4(A0)                      | rect.bottom = old bottom
    ADD.W       (A3),D0                         | D0 = new bottom
    MOVE.W      D0,(A0)                         | rect.top = new bottom
    MOVE.W      #0x8002,0x2(A0)                 | rect.left = full-line marker
    MOVE.W      #0x7FF0,0x6(A0)                 | rect.right = past-line marker
    MOVE.L      A0,-(A7)                        | push rect
    _EraseRect                                  | erase shrunk-away portion
TE_RECALC_LINES_REDRAW:
    MOVEQ.L     #-0x1,D7                        | D7 = -1 (draw mode)
    BRA.W       P_doTEDoText                    | redraw all lines
| ----------------------------------------------------------
| TEDELETE_CONT_3 - hookable trampoline to (0x7F8) lowmem.
| TEFindWord hook entry; tail-calls user proc.
| ----------------------------------------------------------
TEDELETE_CONT_3:
    MOVE.L      (0x7F8).W,-(A7)                 | push hook proc address
    RTS                                         | tail-call to TEFindWord hook
| ----------------------------------------------------------
| XFINDWORD - default TEFindWord implementation.
| In: D0 = char offset, D2 high word = flags.
| Out: D0,D1 = word start/end offsets.
| Scans backward from D0 to find word start, then forward
| from D0 to find word end via the teWordBreak hook.
| ----------------------------------------------------------
XFINDWORD:
    SWAP.W      D2                              | save D2 high word
    MOVE.W      D0,D2                           | D2 = original char pos
    MOVE.W      D0,D1                           | D1 = scan-forward pos
    BEQ.B       TEFINDWORD_SKIP                 | at offset 0 -> only scan forward
    BSR.B       TEFINDWORD_CONT_2               | scan backward for word start
TEFINDWORD_SKIP:
    BCLR        #0x11,D2                        | clear backward-scan flag
TEFINDWORD_CONT:
    CMP.W       0x3C(A3),D1                     | past teLength?
    BCC.B       TEFINDWORD_DONE                 | yes -> stop at end
    MOVEA.W     D1,A1                           | A1 = current scan pos
    BSR.B       TEFINDWORD_CONT_4               | call wdBreak hook
    BNE.B       TEFINDWORD_DONE                 | break char -> word ends here
    ADDQ.W      #0x1,D1                         | next char
    BRA.B       TEFINDWORD_CONT                 | continue scan
TEFINDWORD_DONE:
    RTS                                         | return from TEFINDWORD_DONE
| ----------------------------------------------------------
| TEFINDWORD_CONT_2 - scan backward for word start.
| ----------------------------------------------------------
TEFINDWORD_CONT_2:
    BSET        #0x11,D2                        | set backward-scan flag
TEFINDWORD_CONT_3:
    SUBQ.W      #0x1,D0                         | step backward
    MOVEA.W     D0,A1                           | A1 = current pos
    BSR.B       TEFINDWORD_CONT_4               | call wdBreak hook
    BNE.B       TEFINDWORD_FOUND                | break char -> stop
    TST.W       D0                              | at offset 0?
    BEQ.B       TEFINDWORD_DONE_2               | yes -> stop
    BRA.B       TEFINDWORD_CONT_3               | continue scan
TEFINDWORD_FOUND:
    ADDQ.W      #0x1,D0                         | back up past break char
TEFINDWORD_DONE_2:
    RTS                                         | return from TEFINDWORD_FOUND
| ----------------------------------------------------------
| TEFINDWORD_CONT_4 - invoke teWordBreak hook for one char.
| In: A1 = char offset.
| Calls hook with A0 = text ptr, D0 = offset.
| Out: Z flag from hook (Z=non-break, NZ=break char).
| ----------------------------------------------------------
TEFINDWORD_CONT_4:
    MOVEM.L     D0/A0-A1,-(A7)                  | save scratch
    MOVE.W      A1,D0                           | D0 = char offset
    MOVEA.L     0x3E(A3),A0                     | A0 = text handle
    MOVEA.L     (A0),A0                         | A0 = text ptr
    MOVEA.L     0x26(A3),A1                     | A1 = teWordBreak hook
    JSR         (A1)                            | call hook proc
    MOVEM.L     (A7)+,D0/A0-A1                  | restore scratch
    RTS                                         | return from TEFINDWORD_CONT_4
| ----------------------------------------------------------
| P_TEWdBreak - default word-break detection: chars <= space.
| In: A0 = text ptr, D0 = char offset.
| Out: Z flag (Z=word char, NZ=break char).
| The trailing block is a hookable trampoline to P_XTrimMeasure
| (used to recompute line widths when wdBreak ratifies).
| ----------------------------------------------------------
P_TEWdBreak:
    ANDI.L      #0xFFFF,D0                      | mask offset to 16 bits
    CMPI.B      #0x20,0x0(A0,D0.L)              | char[D0] <= space?
    SLS.B       D0                              | D0 = $FF if break, else 0
    TST.B       D0                              | set CCR
    RTS                                         | return from P_TEWdBreak
    MOVEM.L     D6-D7,-(A7)                     | save D6-D7
    BSR.W       P_XTrimMeasure                  | invoke trim-measure hook
    MOVEM.L     (A7)+,D6-D7                     | restore D6-D7
    RTS                                         | return from P_TEWdBreak
| ----------------------------------------------------------
| TE_FIND_LINE_BREAK - find pixel offset where line breaks (D6..D7).
| In: D6 = line start, D7 = line end, D4 = available pixels.
| Out: D0 = found-flag (0 = wraps), D1 = char where wrap.
| Walks chars (or style runs for styled TE) calling
| P_Pixel2Char to find where we exceed D4 pixels of width.
| ----------------------------------------------------------
TE_FIND_LINE_BREAK:
    MOVEM.L     D2-D3/D5/A2,-(A7)               | save scratch
    TST.W       0x50(A3)                        | styled TE?
    BMI.B       TE_FIND_LINE_BREAK_STYLED       | yes -> walk runs
    MOVE.W      D7,D0                           | D0 = end char
    MOVE.W      D6,D1                           | D1 = start char
    BSR.W       TE_FIND_LINE_MEASURE            | measure D6..D7 in pixels
    ADD.W       D6,D1                           | D1 = wrap char (absolute)
    BRA.W       TE_FIND_LINE_BREAK_RTS          | -> exit
TE_FIND_LINE_BREAK_STYLED:
    MOVE.W      D6,D5                           | D5 = first char
    MOVE.W      D6,D3                           | D3 = current scan pos
    MOVE.W      D3,D0                           | D0 = same
    BSR.W       DateToSeconds                   | locate first style run
    MOVEA.L     A0,A2                           | A2 = run pointer
    MOVE.W      D7,D1                           | D1 = end char
    BSR.W       CountRunsBefore                 | count runs in range
    MOVE.W      D0,D2                           | D2 = run count
TE_FIND_LINE_BREAK_RUN_LOOP:
    MOVEA.L     A2,A0                           | A0 = current run
    BSR.W       SetPortFromStyleRun             | apply run's font
    ADDQ.L      #0x4,A2                         | next run header
    MOVEA.L     A2,A0                           | A0 = next run ptr
    MOVE.W      (A0),D0                         | D0 = next run's start
    CMP.W       D0,D7                           | end before next run?
    BCC.B       TE_FIND_LINE_BREAK_USE_END      | no -> measure to next run
    MOVE.W      D7,D0                           | yes -> measure to D7
TE_FIND_LINE_BREAK_USE_END:
    MOVE.W      D3,D1                           | D1 = current run start
    MOVE.W      D0,D3                           | D3 = next start (advance)
    BSR.W       TE_FIND_LINE_MEASURE            | measure D1..D0 in pixels
    ADD.W       D1,D5                           | accumulate start
    TST.W       D0                              | wrap occurred?
    BNE.B       TE_FIND_LINE_BREAK_FOUND        | yes -> stop
    SUBQ.W      #0x1,D2                         | one less run
    BNE.B       TE_FIND_LINE_BREAK_RUN_LOOP     | more runs -> continue
TE_FIND_LINE_BREAK_FOUND:
    MOVE.W      D5,D1                           | D1 = wrap char (absolute)
TE_FIND_LINE_BREAK_RTS:
    MOVEM.L     (A7)+,D2-D3/D5/A2               | restore scratch
    RTS                                         | return from TE_FIND_LINE_BREAK
| ----------------------------------------------------------
| TE_FIND_LINE_MEASURE - measure chars D1..D0 in current font.
| Calls P_Pixel2Char with D4 = remaining pixel budget.
| Out: D0 = chars consumed (high word = found flag),
|      D4 -= consumed pixels.
| ----------------------------------------------------------
TE_FIND_LINE_MEASURE:
    MOVE.W      D2,-(A7)                        | save D2
    SUB.W       D1,D0                           | D0 = chars in range
    MOVEA.L     0x3E(A3),A0                     | A0 = text handle
    MOVEA.L     (A0),A0                         | A0 = text ptr
    ADDA.W      D1,A0                           | A0 = text + start
    MOVE.W      D4,D1                           | D1 = pixel budget
    MOVEQ.L     #0x0,D2                         | D2 = 0 (initialize)
    BSR.W       P_Pixel2Char                    | measure -> D0=chars, D1=pixels
    SUB.W       D0,D4                           | D4 -= consumed pixels
    SWAP.W      D0                              | D0.H = found flag
    MOVE.W      (A7)+,D2                        | restore D2
    RTS                                         | return from TE_FIND_LINE_MEASURE
| ----------------------------------------------------------
| P_TEWDBREAK_NEXT - hookable trampoline to (0x7FC) lowmem.
| Stacked-RTS tail-call to TENext word-break hook.
| ----------------------------------------------------------
P_TEWDBREAK_NEXT:
    MOVE.L      (0x7FC).W,-(A7)                 | push hook proc address
    RTS                                         | tail-call to TENext hook
| ----------------------------------------------------------
| XFINDLINE - default line-break finder.
| In: D6 = char offset to start scanning from.
| Out: D0 = char offset where line breaks.
| Iterates: at each position, calls TEFindWord (D2=$C: word-
| start mode) to advance to a word boundary, then TE_FIND_LINE_BREAK
| to test if word fits in remaining width. CR forces break.
| crOnly mode (0x48(A3)) skips word-fit testing.
| ----------------------------------------------------------
XFINDLINE:
    MOVEM.L     D1-D7/A1-A2,-(A7)               | save scratch
    MOVE.W      0x6(A3),D4                      | D4 = teViewRect.right
    SUB.W       0x2(A3),D4                      | D4 = view width
    SUBQ.W      #0x1,D4                         | D4 = max line pixels
    SUBA.L      A2,A2                           | A2 = 0 (word counter)
    MOVE.W      D6,D7                           | D7 = scan pos
    MOVEQ.L     #0x0,D3                         | D3 = 0
    MOVEQ.L     #0x0,D5                         | D5 = 0
TEFINDLINE_CONT:
    MOVE.W      D7,D0                           | D0 = current pos
    MOVEQ.L     #0xC,D2                         | D2 = 12 (TEFindWord mode 12)
    BSR.W       TEDELETE_CONT_3                 | call TEFindWord hook
    MOVE.W      D1,D7                           | D7 = next word boundary
    TST.B       0x48(A3)                        | crOnly mode?
    BNE.B       TEFINDLINE_SKIP                 | yes -> skip width check
    BSR.W       TE_FIND_LINE_BREAK              | does word fit in width?
    TST.W       D0                              | result
    BNE.B       TEFINDLINE_OK                   | no -> wrap here
TEFINDLINE_SKIP:
    MOVE.W      D7,D5                           | D5 = line end candidate
    ADDQ.W      #0x1,A2                         | one more word fits
    CMP.W       0x3C(A3),D7                     | reached teLength?
    BEQ.B       TEFINDLINE_EXIT                 | yes -> done
    MOVEA.L     0x3E(A3),A0                     | A0 = text handle
    MOVEA.L     (A0),A0                         | A0 = text ptr
    .byte 0xCE,0xBA,0xFF,0x28                   | AND.L (TEPHysMask).W,D7 (mask)
    CMPI.B      #0xD,0x0(A0,D7.L)               | char[D7] is CR?
    BNE.B       XFINDLINE_NEXT_WORD             | no -> continue scan
    ADDQ.W      #0x1,D5                         | include CR in line
    BRA.B       TEFINDLINE_EXIT                 | -> done
XFINDLINE_NEXT_WORD:
    MOVE.W      D7,D6                           | save end of word
    ADDQ.W      #0x1,D7                         | step past delimiter
    BRA.B       TEFINDLINE_CONT                 | continue scanning
TEFINDLINE_OK:
    MOVE.W      A2,D0                           | any words fit?
    BEQ.B       XFINDLINE_FORCE_BREAK           | none -> force-break char
    MOVEA.L     0x3E(A3),A0                     | A0 = text handle
    MOVEA.L     (A0),A0                         | A0 = text ptr
XFINDLINE_SKIP_SPACE:
    ADDQ.W      #0x1,D5                         | skip trailing space
    CMP.W       0x3C(A3),D5                     | past teLength?
    BCC.B       TEFINDLINE_EXIT                 | yes -> done
    CMPI.B      #0x20,0x0(A0,D5.W)              | char is space?
    BEQ.B       XFINDLINE_SKIP_SPACE            | yes -> keep skipping
    BRA.B       TEFINDLINE_EXIT                 | -> done
XFINDLINE_FORCE_BREAK:
    SUBQ.W      #0x1,D1                         | back up by 1
    MOVE.W      D1,D5                           | D5 = forced break pos
TEFINDLINE_EXIT:
    MOVE.W      D5,D0                           | D0 = line end offset
    MOVEM.L     (A7)+,D1-D7/A1-A2               | restore scratch
    RTS                                         | return from XFINDLINE
| ----------------------------------------------------------
| P_doTERecal - hookable trampoline to (TERecal) lowmem.
| Stacked-RTS tail-call to user's recalc proc.
| ----------------------------------------------------------
P_doTERecal:
    MOVE.L      (TERecal).W,-(A7)               | push hook proc address
    RTS                                         | tail-call to hook
| ----------------------------------------------------------
| P_TERecal - default recalc proc: rebuild lineStarts array.
| In: A3 = TERec, on entry teLineStarts is invalid.
| Locals: -0x2 = saved teLength, -0x4 = char at change point,
|         -0xE = saved old nLines.
| Walks chars from selStart looking for line breaks via
| XFINDLINE; updates lineStarts and nLines.
| ----------------------------------------------------------
P_TERecal:
    LINK        A6,#-0xE                        | 14 bytes locals
    MOVEM.L     D3/D5-D6/A2,-(A7)               | save scratch
    MOVE.W      0x5E(A3),-0xE(A6)               | save old nLines
    CLR.W       0x5E(A3)                        | nLines = 0 (rebuilding)
    CLR.W       -0x4(A6)                        | clear local at -0x4
    MOVE.W      0x3C(A3),-0x2(A6)               | save teLength
    TST.W       0x3C(A3)                        | empty TE?
    BEQ.W       P_TERECAL_STYLED_HEIGHT         | yes -> finalize
    LEA.L       0x60(A3),A2                     | A2 = lineStarts base
    MOVEQ.L     #0x10,D2                        | D2 = 0x10 (mode flag)
    MOVE.W      0x20(A3),D0                     | D0 = teSelStart (change point)
    BSR.W       TEDELETE_CONT_3                 | TEFindWord (mode 0x10)
    MOVE.W      D0,D3                           | D3 = scan position
| Walk existing lineStarts to find which line contains selStart.
P_TERECAL_NEXT:
    MOVE.W      (A2)+,D6                        | D6 = next lineStart
    MOVE.W      D6,-0x4(A6)                     | save as change-point local
    CMP.W       (A2),D3                         | scan position < next lineStart ?
    BCS.B       TECut                           | yes, found containing line
    BEQ.B       P_TERECAL_BOUNDARY              | exactly at boundary, special case
    ADDQ.W      #0x1,0x5E(A3)                   | else inc nLines (skip this line)
    BRA.B       P_TERECAL_NEXT                  | next lineStart
TECut:
    BSR.W       P_TEWDBREAK_NEXT                | find next break boundary
    CMP.W       D0,D3                           | scan past break ?
    BCC.B       P_TERECAL_DONE                  | yes, no rewind needed
| Decide whether to rewind to start of current word.
P_TERECAL_CONT:
    TST.B       (WordRedraw).W                  | WordRedraw mode ?
    BGT.B       P_TERECAL_DONE                  | > 0, no rewind
    BLT.B       P_TERECAL_DISPATCH              | < 0, skip rewind heuristic
    MOVE.W      0x20(A3),D3                     | rewind D3 to teSelStart
P_TERECAL_DONE:
    TST.W       0x3A(A3)                        | teCrOnly set ?
    BNE.B       P_TERECAL_DISPATCH              | yes, skip per-word rewind
    TST.W       (TESysJust).W                   | system right-aligned ?
    BNE.B       P_TERECAL_DISPATCH              | yes, skip rewind
    MOVE.W      D3,-0x4(A6)                     | save change point
    BEQ.B       P_TERECAL_DISPATCH              | at offset 0, no -1 needed
    SUBQ.W      #0x1,-0x4(A6)                   | back up 1 char (rewind to prev)
    BRA.B       P_TERECAL_DISPATCH              | go to recalc dispatch
P_TERECAL_BOUNDARY:
    BSR.W       P_TEWDBREAK_NEXT                | find break at boundary
    CMP.W       D0,D3                           | break == scan ?
    BNE.B       P_TERECAL_DONE                  | no, normal handling
    MOVE.W      D3,-0x4(A6)                     | yes, change point = D3
    BRA.B       P_TERECAL_CONT                  | continue
| Dispatch to in-place recalc (TE_INPLACE_LINESTARTS) or full rebuild (TE_FULL_REBUILD_LINESTARTS).
| Called by: P_TERECAL_DONE, P_TERECAL_CONT
P_TERECAL_DISPATCH:
    MOVE.W      D0,D3                           | D3 = scan position
    TST.W       D7                              | text growing (D7 > 0) ?
    BLE.B       P_TERECAL_FULL_REBUILD          | no, do full rebuild
    BSR.B       TE_INPLACE_LINESTARTS           | yes, in-place lineStarts patch
    BRA.B       P_TERECAL_STYLED_HEIGHT         | go to common epilogue
P_TERECAL_FULL_REBUILD:
    BSR.W       TE_FULL_REBUILD_LINESTARTS      | full rebuild via aux buffer
P_TERECAL_STYLED_HEIGHT:
    BSR.W       TE_REBUILD_LINEHEIGHTS          | restore lineStart compaction
    MOVE.W      -0x2(A6),D4                     | D4 = teLength (saved)
    MOVE.W      -0x4(A6),D2                     | D2 = change point
    MOVEM.L     (A7)+,D3/D5-D6/A2               | restore scratch
    UNLK        A6                              | release frame
    RTS                                         | return from P_TERecal
| ----------------------------------------------------------
|
| TE_INPLACE_LINESTARTS -- in-place lineStarts patcher (text grew, D7 > 0)
|
| Walks the existing teLineStarts array (A2) past the change point,
| inserting new lineStarts where word breaks now fall and shifting
| trailing entries by D7 (insertion size). Uses _TEWDBreak hook to
| find next word break.
|
| In: A2 -> next teLineStarts slot to write, D3 = scan position,
| D6 = scratch, D7 = insertion size in chars. -0xC(A6) tracks
| furthest already-shifted trailing slot.
|
TE_INPLACE_LINESTARTS:
    MOVEA.L     0x3E(A3),A0                     | A0 = TERec.hText (handle)
    MOVEA.L     (A0),A1                         | A1 = text master ptr
TE_INPLACE_LINESTARTS_LOOP:
    CMP.W       0x22(A3),D3                     | scan past teSelEnd ?
    BLS.B       P_TERECAL_NEXT_3                | yes (or =), force a new break
    MOVE.L      A2,-0xC(A6)                     | save trailing-shift cursor
    MOVE.W      (A2),D0                         | D0 = next existing lineStart
    SUB.W       D3,D0                           | D0 = lineStart - scan pos
    CMP.W       D0,D7                           | insertion exactly closes gap ?
    BEQ.B       TE_INPLACE_LINESTARTS_COPY_TAIL | yes, jump to copy tail
    CMPI.B      #0xD,-0x1(A1,D3.W)              | char before scan == CR ?
    BNE.B       P_TERECAL_NEXT_3                | no, force break
| Walk lineStarts forward to the slot whose value > scan + insert.
    MOVEA.L     A2,A0                           | A0 -> current lineStarts slot
    MOVE.W      D3,D0                           | D0 = scan position
    ADD.W       D7,D0                           | D0 += insertion (post-edit pos)
TE_INPLACE_LINESTARTS_FORWARD:
    CMP.W       (A0)+,D0                        | post-edit pos > slot ?
    BHI.B       TE_INPLACE_LINESTARTS_FORWARD   | yes, advance
    SUBQ.W      #0x2,A0                         | back up one slot
    MOVE.L      A0,-0xC(A6)                     | save trailing-shift cursor
    BRA.B       TE_INPLACE_LINESTARTS_COPY_TAIL | go to copy tail
P_TERECAL_NEXT_3:
    ADDQ.W      #0x1,0x5E(A3)                   | nLines++
    MOVE.W      D3,(A2)+                        | append new lineStart
    MOVE.W      D3,D6                           | D6 = current pos
    CMP.W       0x3C(A3),D6                     | past teLength ?
    BCC.B       TE_INPLACE_LINESTARTS_RTS       | yes, done
    BSR.W       P_TEWDBREAK_NEXT                | find next word break
    MOVE.W      D0,D3                           | D3 = next break pos
    BRA.B       TE_INPLACE_LINESTARTS_LOOP      | continue loop
TE_INPLACE_LINESTARTS_COPY_TAIL:
    MOVEA.L     A2,A0                           | A0 -> last appended slot
    MOVEA.L     -0xC(A6),A0                     | restore A0 = trailing-shift cursor
    CMPA.L      A2,A0                           | nothing to shift ?
    BEQ.B       P_TERECAL_OK_2                  | yes, skip shift loop
    MOVE.W      0x3C(A3),D3                     | else D3 = teLength sentinel
P_TERECAL_OK_2:
    MOVE.W      D3,-0x2(A6)                     | save change point
TE_INPLACE_LINESTARTS_SHIFT:
    ADDQ.W      #0x1,0x5E(A3)                   | nLines++
    MOVE.W      (A0)+,D0                        | D0 = old lineStart
    SUB.W       D7,D0                           | undo old offset
    MOVE.W      D0,(A2)                         | install adjusted value
    MOVE.W      (A2)+,D6                        | D6 = new lineStart
    CMP.W       0x3C(A3),D6                     | past teLength ?
    BCS.B       TE_INPLACE_LINESTARTS_SHIFT     | no, continue shift
TE_INPLACE_LINESTARTS_RTS:
    RTS                                         | return from TE_INPLACE_LINESTARTS
| ----------------------------------------------------------
|
| TE_FULL_REBUILD_LINESTARTS -- full lineStarts rebuild via auxiliary buffer
|
| Used when text shrunk (D7 <= 0). Allocates a 256-byte working
| buffer (grows by +256 if needed), accumulates new lineStart
| positions there, then _Munger-replaces the old teLineStarts
| range with the new buffer contents.
|
| Locals:
|   -0x8  L  aux buffer handle
|   -0xC  L  trailing-shift cursor
|   -0xE  W  saved old nLines
|   -0x2  W  saved teLength change point
|
TE_FULL_REBUILD_LINESTARTS:
    MOVEM.L     D2/D4,-(A7)                     | save D2,D4
    MOVEQ.L     #0x0,D5                         | D5 = 0 (output cursor in buf)
    MOVE.W      0x22(A3),D4                     | D4 = teSelEnd
    SUB.W       D7,D4                           | D4 -= delta (post-edit selEnd)
    SUBA.L      A3,A2                           | A2 -> relative to A3 (handle-safe)
    MOVE.L      #0x100,D0                       | D0 = 256 bytes initial alloc
    MOVE.L      D0,D2                           | D2 = current buf size
    BSR.W       TE_RESIZE_AND_DEREF             | allocate aux buf
    _HLock                                      | lock buf for direct write
    MOVEA.L     (A0),A1                         | A1 = buf master ptr
    MOVE.L      A0,-0x8(A6)                     | save buf handle
    ADDA.L      A3,A2                           | A2 = absolute again
    MOVE.L      A2,-0xC(A6)                     | save trailing-shift cursor
TE_FULL_REBUILD_LOOP:
    CMP.W       D4,D3                           | scan past adjusted selEnd ?
    BLS.B       TE_FULL_REBUILD_GROW_BUF        | yes, force new break
    MOVEA.L     0x3E(A3),A0                     | A0 = TERec.hText
    MOVEA.L     (A0),A0                         | A0 = text master ptr
    CMPI.B      #0xD,-0x1(A0,D3.W)              | char before scan == CR ?
    BNE.B       TE_FULL_REBUILD_CHK_INSERT      | no, check for break boundary
    MOVEA.L     A2,A0                           | A0 -> teLineStarts cursor
    MOVE.W      D3,D0                           | D0 = scan
    ADD.W       D7,D0                           | D0 += delta (pre-edit pos)
TE_FULL_REBUILD_FORWARD:
    CMP.W       (A0)+,D0                        | walk past slots <= D0
    BHI.B       TE_FULL_REBUILD_FORWARD         | continue
    SUBQ.W      #0x2,A0                         | back up one slot
    MOVE.L      A0,-0xC(A6)                     | save trailing-shift cursor
    BRA.B       TE_FULL_REBUILD_FINALIZE        | exit walk, do _Munger
TE_FULL_REBUILD_CHK_INSERT:
    MOVE.W      0x0(A2,D5.L),D0                 | D0 = pre-edit lineStart at output cursor
    SUB.W       D3,D0                           | D0 -= scan
    CMP.W       D0,D7                           | matches insertion size ?
    BNE.B       TE_FULL_REBUILD_GROW_BUF        | no, force break
    ADD.L       D5,-0xC(A6)                     | shift cursor by output count
    BRA.B       TE_FULL_REBUILD_FINALIZE        | exit walk
TE_FULL_REBUILD_GROW_BUF:
    CMP.L       D5,D2                           | output cursor past buf end ?
    BGT.B       TE_FULL_REBUILD_APPEND          | no, write next slot
    MOVEA.L     -0x8(A6),A0                     | A0 = buf handle
    _HUnlock                                    | unlock for grow
    ADDI.L      #0x100,D2                       | grow by +256
    MOVE.L      D2,D0                           | D0 = new size
    SUBA.L      (A0),A1                         | A1 -> offset within buf
    BSR.W       TE_RESIZE_TEXTHANDLE            | _SetHandleSize
    _HLock                                      | re-lock
    ADDA.L      (A0),A1                         | restore A1 to master+offset
TE_FULL_REBUILD_APPEND:
    MOVE.W      D3,(A1)+                        | append new lineStart to buf
    MOVE.W      D3,D6                           | D6 = current pos
    ADDQ.W      #0x1,0x5E(A3)                   | nLines++
    ADDQ.L      #0x2,D5                         | output cursor += 2
    CMP.W       0x3C(A3),D6                     | past teLength ?
    BCS.B       TE_FULL_REBUILD_NEXT_BREAK      | no, find next break
    MOVE.W      -0xE(A6),D0                     | D0 = saved old nLines
    ADDQ.W      #0x1,D0                         | + 1
    ADD.W       D0,D0                           | * 2 (word stride)
    LEA.L       0x60(A3,D0.W),A0                | A0 -> end of teLineStarts
    MOVE.L      A0,-0xC(A6)                     | save trailing-shift cursor (= end)
    BRA.B       TE_FULL_REBUILD_DO_MUNGER       | exit walk
TE_FULL_REBUILD_NEXT_BREAK:
    BSR.W       P_TEWDBREAK_NEXT                | find next word break
    MOVE.W      D0,D3                           | D3 = next break pos
    BRA.B       TE_FULL_REBUILD_LOOP            | continue scan
TE_FULL_REBUILD_FINALIZE:
    MOVE.W      D3,-0x2(A6)                     | save change point
    TST.L       D5                              | wrote anything to buf ?
    BEQ.W       TE_FULL_REBUILD_DISPOSE_BUF     | no, skip _Munger
    MOVE.L      -0xC(A6),D0                     | D0 = trailing-shift cursor
    SUB.L       A2,D0                           | offset from buf start
    SUB.L       D5,D0                           | minus output count
    BEQ.B       TE_FULL_REBUILD_DO_MUNGER       | exact match, skip teLength fix
    MOVE.W      0x3C(A3),D3                     | D3 = teLength sentinel
TE_FULL_REBUILD_DO_MUNGER:
    MOVE.W      D3,-0x2(A6)                     | save change point
| _Munger params: replace teLineStarts[A2-A3..-0xC(A6)-A3] with
| buf contents (D5 bytes, ptr from -0x8(A6)).
    MOVEA.L     A4,A0                           | A0 = teLineStarts handle (?)
    _HUnlock                                    | unlock teLineStarts
    SUBQ.L      #0x4,A7                         | reserve _Munger result
    MOVE.L      A4,-(A7)                        | push lineStarts handle
    MOVE.L      A2,D0                           | D0 = A2 (curr pos)
    SUB.L       A3,D0                           | offset from teLineStarts base
    MOVE.L      D0,-(A7)                        | push offset
    CLR.L       -(A7)                           | matchPtr = nil
    MOVE.L      -0xC(A6),D0                     | D0 = trailing-shift cursor
    SUB.L       A2,D0                           | length to delete
    MOVE.L      D0,-(A7)                        | push delete length
    MOVEA.L     -0x8(A6),A0                     | A0 = buf handle
    MOVE.L      (A0),-(A7)                      | push buf master ptr (replace src)
    MOVE.L      D5,-(A7)                        | push replace length
    SUBA.L      A3,A2                           | A2 -> relative again
    _Munger                                     | replace lineStarts range with buf
    ADDQ.L      #0x4,A7                         | drop result
    MOVEA.L     A4,A0                           | A0 = teLineStarts handle
    _HLock                                      | re-lock for further work
    MOVEA.L     (A4),A3                         | A3 = teLineStarts master ptr (?)
    ADDA.L      A3,A2                           | A2 = absolute (post-edit)
    ADDA.L      D5,A2                           | A2 += output count
TE_FULL_REBUILD_DISPOSE_BUF:
    MOVEA.L     -0x8(A6),A0                     | A0 = aux buf handle
    _DisposeHandle                              | release buffer
    CMP.W       0x3C(A3),D6                     | scan ended past teLength ?
    BCC.B       TE_FULL_REBUILD_RTS             | yes, no trailing fix
TE_FULL_REBUILD_TAIL_SHIFT:
    ADDQ.W      #0x1,0x5E(A3)                   | nLines++
    SUB.W       D7,(A2)                         | undo old offset
    MOVE.W      (A2)+,D6                        | D6 = adjusted lineStart
    CMP.W       0x3C(A3),D6                     | past teLength ?
    BCS.B       TE_FULL_REBUILD_TAIL_SHIFT      | no, continue shift
TE_FULL_REBUILD_RTS:
    MOVEM.L     (A7)+,D2/D4                     | restore D2,D4
    RTS                                         | return from TE_FULL_REBUILD_LINESTARTS
| ----------------------------------------------------------
|
| TE_REBUILD_LINEHEIGHTS -- styled-TextEdit per-line height table rebuild
|
| For styled TE, walks the per-line styleRun + lineHeights table
| recomputing each line's height from the maximum style-run
| height. Empty TE (teLength = 0) gets a single line whose
| height comes from the default style.
|
| Locals (relative to A6):
|   -0x2  W  saved teLength change point
|   -0xE  W  saved old nLines
|   -0x4  W  saved teLine.bottom for redraw bounds
|
TE_REBUILD_LINEHEIGHTS:
    MOVEM.L     D2-D5/A2/A4,-(A7)               | save scratch regs
    TST.W       0x50(A3)                        | TERec.teStyleRec set ?
    BPL.W       TE_REBUILD_LH_RTS               | no, plain TE -> done
    MOVEA.L     0x4A(A3),A0                     | A0 = StyleRec handle
    MOVEA.L     (A0),A0                         | deref to StyleRec
    MOVEA.L     0x8(A0),A0                      | A0 = lineHeights handle
    _GetHandleSize                              | D0 = byte size of lineHeights
    MOVE.W      D0,D3                           | D3 = byte size
    ASR.W       #0x2,D3                         | D3 = entry count (4 bytes each)
    MOVEQ.L     #0x0,D0                         | clear D0 high
    MOVE.W      0x5E(A3),D0                     | D0 = nLines
    ADDQ.L      #0x1,D0                         | + 1 (terminator entry)
    LSL.L       #0x2,D0                         | * 4 (long entries)
    BSR.W       TE_RESIZE_TEXTHANDLE            | resize lineHeights to fit
    MOVEA.L     0x4A(A3),A1                     | A1 = StyleRec handle
    MOVEA.L     (A1),A1                         | deref to StyleRec
    MOVEA.L     0x8(A1),A4                      | A4 = lineHeights handle
    MOVEA.L     (A4),A4                         | A4 = lineHeights master ptr
    TST.W       0x3C(A3)                        | teLength == 0 (empty) ?
    BNE.B       TE_REBUILD_LH_WALK              | no, walk runs to compute heights
| Empty-TE special case: write one line with default style metrics.
    MOVEA.L     0x52(A3),A0                     | A0 = teInPort
    MOVE.W      0x44(A0),-(A7)                  | save teInPort.txMode
    CLR.W       0x44(A0)                        | txMode := 0
    BSR.W       TE_GET_FONT_INFO                | get default lineHeight + ascent
    MOVE.W      D1,(A4)+                        | lineHeights[0].height := D1
    MOVE.W      D0,(A4)                         | lineHeights[0].ascent := D0
    MOVEA.L     0x52(A3),A0                     | A0 = teInPort
    MOVE.W      (A7)+,0x44(A0)                  | restore teInPort.txMode
    BRA.W       TE_REBUILD_LH_RTS               | done
| TE_REBUILD_LH_WALK -- per-line height computation walk
|
| For each line: walks all style runs covering this line,
| computing max(line height) from each run's styleEntry metrics
| (height at +2, ascent at +4 within the 18-byte styleEntry).
| Stores the computed (height, ascent) into A4+0..+2.
|
| Inputs:
|   A1 -> styleRun array (after header)
|   A0 -> styleEntry table
|   A2 -> teLineStarts cursor
|   A4 -> lineHeights output cursor
|   D2  = current line index
|   D3  = entry count from TE_REBUILD_LINEHEIGHTS prologue
|   D4  = line index where height first changed (or -1)
|   D5  = previous line's height (for change detect)
TE_REBUILD_LH_WALK:
    MOVEA.L     0x4(A1),A0                      | A0 = styleEntry handle
    MOVEA.L     (A0),A0                         | deref to styleEntry table
    LEA.L       0x14(A1),A1                     | A1 -> first styleRun (after header)
    LEA.L       0x60(A3),A2                     | A2 -> teLineStarts base
    MOVEQ.L     #0x0,D1                         | D1 = max line height = 0
    MOVEQ.L     #0x0,D2                         | D2 = current line index = 0
    MOVEQ.L     #-0x1,D4                        | D4 = -1 (first-changed line sentinel)
    MOVE.W      (A4),D5                         | D5 = old line height
TE_REBUILD_LH_RUN_LOOP:
    MOVE.W      0x2(A1),D0                      | D0 = styleRun.styleIndex
    MULU.W      #0x12,D0                        | * 18 (sizeof styleEntry)
    CMP.W       0x2(A0,D0.L),D1                 | run.height > current max ?
    BGE.B       TE_REBUILD_LH_NEXT_RUN          | no, skip update
    MOVE.W      0x2(A0,D0.L),D1                 | D1 := run.height (new max)
    CMP.W       D2,D3                           | line index < initial nLines ?
    BLE.B       TE_REBUILD_LH_STORE             | yes, can grow shrunk-flag
    TST.W       (A4)                            | first time setting this line ?
    BMI.B       TE_REBUILD_LH_NEXT_RUN          | yes, skip
TE_REBUILD_LH_STORE:
    MOVE.W      D1,(A4)                         | lineHeights.height := D1
    MOVE.W      0x4(A0,D0.L),0x2(A4)            | lineHeights.ascent := run.ascent
TE_REBUILD_LH_NEXT_RUN:
    MOVE.W      0x2(A2),D0                      | D0 = next teLineStart
    CMP.W       0x4(A1),D0                      | next line < run.endChar ?
    BCS.B       TE_REBUILD_LH_NEXT_LINE         | yes, advance line cursor only
    BEQ.B       TE_REBUILD_LH_BOTH              | exact match: advance both
    ADDQ.L      #0x4,A1                         | next styleRun
    BRA.B       TE_REBUILD_LH_RUN_LOOP          | continue current line
TE_REBUILD_LH_BOTH:
    ADDQ.L      #0x4,A1                         | (also advance styleRun)
TE_REBUILD_LH_NEXT_LINE:
    ADDQ.L      #0x2,A2                         | next teLineStart
    TST.L       D4                              | already noted first-changed line ?
    BPL.B       TE_REBUILD_LH_AFTER_DETECT      | yes, skip detect
    CMP.W       (A4),D5                         | height changed ?
    BEQ.B       TE_REBUILD_LH_AFTER_DETECT      | no
    MOVEQ.L     #0x0,D4                         | yes, record this line index
    MOVE.W      D2,D4                           | D4 = first-changed line
TE_REBUILD_LH_AFTER_DETECT:
    ADDQ.L      #0x4,A4                         | next lineHeights entry
    MOVE.W      (A4),D5                         | D5 = next old height
    MOVEQ.L     #0x0,D1                         | D1 = 0 (reset max for next line)
    ADDQ.W      #0x1,D2                         | next line
    CMP.W       0x5E(A3),D2                     | < nLines ?
    BCS.B       TE_REBUILD_LH_RUN_LOOP          | yes, continue
| Done: write terminator and compute redraw bounds.
    MOVE.L      -0x4(A4),(A4)                   | duplicate last entry as terminator
    TST.L       D4                              | any line height changed ?
    BMI.B       TE_REBUILD_LH_RTS               | no, no redraw needed
    MOVE.W      0x3C(A3),-0x2(A6)               | save teLength as change point
    ADD.W       D4,D4                           | * 2 for word stride
    MOVE.W      0x60(A3,D4.W),D0                | D0 = first-changed lineStart
    CMP.W       -0x4(A6),D0                     | already past stored change pt ?
    BCC.B       TE_REBUILD_LH_RTS               | yes, leave alone
    MOVE.W      D0,-0x4(A6)                     | else update change pt
TE_REBUILD_LH_RTS:
    MOVEM.L     (A7)+,D2-D5/A2/A4               | restore scratch
    RTS                                         | return from TE_REBUILD_LINEHEIGHTS
| ----------------------------------------------------------
|
| TE_CARET_RESTORE / TE_CARET_SHOW -- restore caret to visible (post-edit)
|
| If TERec is active and selection is empty (caret), enable the
| blink flag (0x39) and ensure caret is shown (0x38). Falls into
| P_TERECAL_CONT_4 to actually XOR the caret pixels.
|
| Called by: TESETSELECT, TECLICK_UNHIGHLIGHT, TECLICK_SET_CARET, TEDELETE, TE_DO_PASTE_EDIT (and 3 more)
TE_CARET_RESTORE:
    TST.B       0x24(A3)                        | TERec.teActive ?
    BEQ.W       TE_CARET_RTS                    | no, just return
    MOVE.W      0x20(A3),D0                     | D0 = teSelStart
    CMP.W       0x22(A3),D0                     | empty selection (caret) ?
    BNE.B       TE_CARET_RTS                    | no, return (selection visible)
    ST.B        0x39(A3)                        | enable caret blink (0x39 := -1)
TE_CARET_SHOW:
    TST.B       0x38(A3)                        | caret already shown ?
    BNE.B       TE_CARET_RTS                    | yes, nothing to do
    ST.B        0x38(A3)                        | mark caret-shown
TE_CARET_REDRAW:
    BRA.B       P_TERECAL_CONT_4                | XOR caret pixels
| ----------------------------------------------------------
|
| TE_CARET_ERASE -- erase caret (pre-edit)
|
| Disables caret-blink, clears caret-shown flag, then XORs the
| caret pixels off via P_TERECAL_CONT_4. No-op if TERec is inactive.
|
| Called by: TESETSELECT, TECLICK, TECLICK_EMPTY, TEDELETE, TEDEACTIVATE (and 7 more)
TE_CARET_ERASE:
    TST.B       0x24(A3)                        | TERec.teActive ?
    BEQ.W       TE_CARET_RTS                    | no, just return
    SF.B        0x39(A3)                        | disable caret-blink
    TST.B       0x38(A3)                        | caret currently shown ?
    BEQ.B       TE_CARET_RTS                    | no, nothing to erase
    SF.B        0x38(A3)                        | mark caret-not-shown
| ----------------------------------------------------------
|
| P_TERECAL_CONT_4 -- XOR caret pixels at teSelStart
|
| Calls P_TEDoText with mode -2 (caret) over the single-char
| range [teSelStart..teSelStart], then XTRIMMEASURE_CONT_7 to bracket
| the operation with style/font setup tracked via 0x5A(A3).
|
P_TERECAL_CONT_4:
    MOVEM.L     D0-D7,-(A7)                     | save scratch regs
    MOVE.W      0x20(A3),D3                     | D3 = teSelStart
    MOVE.W      D3,D4                           | D4 = teSelStart (end == start)
    MOVEQ.L     #-0x2,D7                        | D7 = -2 (caret mode)
    BSR.W       P_doTEDoText                    | XOR caret pixels
    MOVE.L      0x5A(A3),D0                     | D0 = TERec.teInPort (?)
    BSR.W       XTRIMMEASURE_CONT_7             | post-draw cleanup
    MOVEM.L     (A7)+,D0-D7                     | restore regs
| Called by: TE_CARET_RESTORE, TE_CARET_ERASE, TE_CARET_SHOW
TE_CARET_RTS:
    RTS                                         | return from caret toggle
| ----------------------------------------------------------
| _TEActivate ($A9D8) - activate a TE field (start blinking).
| Pascal: procedure TEActivate(hTE: TEHandle);
| Sets teActive flag, marks for caret blink if no selection,
| highlights selection if any.
| ----------------------------------------------------------
TEACTIVATE:
    BSR.W       TE_PROLOGUE_NODISP              | _TE prologue
    TST.B       0x24(A3)                        | already active?
    BNE.B       TEACTIVATE_OK                   | yes -> nothing to do
    MOVE.W      0x20(A3),D0                     | D0 = teSelStart
    CMP.W       0x22(A3),D0                     | == teSelEnd (insertion point)?
    BNE.B       TEACTIVATE_NO                   | no -> just activate
    ST.B        0x39(A3)                        | yes -> enable caret blink
TEACTIVATE_NO:
    ST.B        0x24(A3)                        | teActive = true
    BSR.W       TEUPDATE_CONT_2                 | highlight selection
TEACTIVATE_OK:
    BRA.B       TE_AD_EPILOGUE                  | -> _TE epilogue
| ----------------------------------------------------------
| _TEDeactivate ($A9D9) - deactivate TE field (stop caret).
| Pascal: procedure TEDeactivate(hTE: TEHandle);
| Hides caret, unhighlights selection, clears teActive flag.
| ----------------------------------------------------------
TEDEACTIVATE:
    BSR.W       TE_PROLOGUE_NODISP              | _TE prologue
    TST.B       0x24(A3)                        | active?
    BEQ.B       TE_AD_EPILOGUE                  | no -> nothing to do
    BSR.B       TE_CARET_ERASE                  | hide caret
    BSR.W       TEUPDATE_CONT_2                 | unhighlight selection
    SF.B        0x24(A3)                        | teActive = false
    BRA.B       TE_AD_EPILOGUE                  | -> _TE epilogue
| ----------------------------------------------------------
| _TEIdle ($A9DA) - blink the caret if blink interval passed.
| Pascal: procedure TEIdle(hTE: TEHandle);
| If caret-blink enabled and CaretTime ticks have elapsed,
| toggle caret state via XOR.
| ----------------------------------------------------------
TEIDLE:
    BSR.W       TE_PROLOGUE_NODISP              | _TE prologue
    TST.B       0x39(A3)                        | caret blink enabled?
    BEQ.B       TE_AD_EPILOGUE                  | no -> done
    SUBQ.W      #0x4,A7                         | room for tick count
    _TickCount                                  | get current ticks
    MOVEA.L     (A7)+,A0                        | A0 = current ticks
    CMPA.L      0x34(A3),A0                     | reached blink time?
    BCS.B       TE_AD_EPILOGUE                  | not yet -> done
    ADDA.L      (CaretTime).W,A0                | next blink = now + CaretTime
    MOVE.L      A0,0x34(A3)                     | save next-blink tick count
    BSR.B       P_TERECAL_CONT_4                | toggle caret pixels
    NOT.B       0x38(A3)                        | flip caret-shown flag
| Called by: TEDEACTIVATE, TEIDLE, TEACTIVATE_OK, TEPASTE
TE_AD_EPILOGUE:
    BRA.W       TECALTEXT_EXIT                  | -> _TE epilogue
| ----------------------------------------------------------
| _TEPaste ($A9DB) - paste TE scrap into selection.
| Pascal: procedure TEPaste(hTE: TEHandle);
| For unstyled TE: pastes text from TEScrpHandle.
| For styled TE: also reads 'styl' resource from system scrap.
| ----------------------------------------------------------
TEPASTE:
    BSR.W       TE_PROLOGUE_NODISP              | _TE prologue
    MOVEQ.L     #0x0,D7                         | D7 = 0 (paste mode)
    BSR.W       TE_PASTE_BODY                   | do paste with scrap
    BRA.B       TE_AD_EPILOGUE                  | -> _TE epilogue
| ----------------------------------------------------------
|
| TE_PASTE_BODY -- shared paste body (TEPaste / TEStylPaste)
|
| For unstyled TE: pastes the TEScrpHandle text directly.
| For styled TE: allocates a temp handle, calls _GetScrap with
| 'TEXT' resType (0x54455854) to fetch the text portion, then
| HLocks and dispatches to TE_DO_PASTE to do the actual edit.
|
TE_PASTE_BODY:
    TST.W       0x50(A3)                        | TERec.teStyleRec set ?
    BPL.B       TE_PASTE_PLAIN                  | no, plain paste path
    MOVEQ.L     #0x0,D0                         | size = 0 (initial alloc)
    BSR.W       TE_RESIZE_AND_DEREF             | allocate temp handle
    MOVE.L      A0,D6                           | D6 = temp handle (saved)
    MOVE.L      A0,-(A7)                        | push handle for DisposeHandle later
    SUBQ.L      #0x4,A7                         | reserve _GetScrap result slot
    MOVEA.L     A7,A1                           | A1 = ptr to result slot
    SUBQ.L      #0x4,A7                         | reserve handle slot
    MOVE.L      A0,-(A7)                        | push destHandle
    MOVE.L      #0x54455854,-(A7)               | resType = 'TEXT'
    MOVE.L      A1,-(A7)                        | push offset slot
    _GetScrap                                   | fetch TEXT from system scrap
    MOVE.L      (A7)+,D0                        | D0 = byte count returned (or err)
    ADDQ.L      #0x4,A7                         | drop offset slot
    TST.L       D0                              | got data ?
    BLE.B       TE_PASTE_DISPOSE_TEMP           | no, just dispose
    MOVE.L      D0,D5                           | D5 = scrap byte count
    MOVEA.L     D6,A0                           | A0 = temp handle
    _HLock                                      | lock for paste
    MOVE.L      (A0),D6                         | D6 = scrap text ptr
    BSR.W       TE_DO_PASTE                     | do paste
TE_PASTE_DISPOSE_TEMP:
    MOVEA.L     (A7)+,A0                        | pop temp handle
    _DisposeHandle                              | discard
    BRA.B       TE_PASTE_BODY_RTS               | done
TE_PASTE_PLAIN:
    MOVEA.L     (TEScrpHandle).W,A0             | A0 = TEScrpHandle (in-process scrap)
    _HLock                                      | lock for paste
    MOVE.L      (A0),D6                         | D6 = TEScrp text ptr
    MOVEQ.L     #0x0,D5                         | clear D5 high
    MOVE.W      (TEScrpLength).W,D5             | D5 = TEScrpLength
    BSR.B       TE_DO_PASTE                     | do paste
    MOVEA.L     (TEScrpHandle).W,A0             | re-load handle
    _HUnlock                                    | unlock
TE_PASTE_BODY_RTS:
    RTS                                         | return from TEPaste body
| ----------------------------------------------------------
|
| TESTYLPASTE_ENTRY -- _TEStylPaste ($A83C) trap entry
|
| Same as TEPaste but D7 = 1 indicates styled paste should also
| read the 'styl' resource via TE_STYL_PASTE. Strips 6 bytes of
| stack params on return.
|
TESTYLPASTE_ENTRY:
    MOVEQ.L     #0x1,D7                         | D7 = 1 (styled paste)
    BSR.B       TE_PASTE_BODY                   | shared paste body
    MOVEQ.L     #0x6,D0                         | D0 = 6 bytes to strip
    BRA.W       TE_EXIT_3PARAM                  | -> common TE epilogue
| ----------------------------------------------------------
|
| TE_DO_PASTE -- core paste implementation
|
| D5 = scrap byte count, D6 = scrap text ptr.
| Hides caret, erases selection, applies style updates (for
| styled TE), then _Munger replaces the selection with the
| scrap text. Updates teLength, recalcs lines via TE_RECALC_LINES,
| advances teSelStart to end of pasted text, restores caret
| and scrolls into view.
|
TE_DO_PASTE:
    MOVE.W      D7,-(A7)                        | save styled-flag
    BSR.W       TE_CARET_ERASE                  | hide caret
    BSR.W       TEUPDATE_CONT_2                 | erase selection
    TST.W       0x50(A3)                        | TERec.teStyleRec set ?
    BPL.B       TE_DO_PASTE_EDIT                | no, plain TE, skip style work
    TST.W       (A7)                            | styled-flag set ?
    BEQ.B       TE_DO_PASTE_COLLAPSE_STYLES     | no, just collapse styles
    BSR.W       TE_STYL_PASTE                   | yes, also paste 'styl' resource
    BRA.B       TE_DO_PASTE_EDIT                | go to text edit
TE_DO_PASTE_COLLAPSE_STYLES:
    BSR.W       TE_PREP_STYLES_FOR_PASTE        | collapse styles in selection
TE_DO_PASTE_EDIT:
    BSR.W       XTRIMMEASURE_CONT_15            | order selection
    MOVE.W      D0,D7                           | D7 = selEnd
    SUB.W       (A2),D7                         | D7 = selLen (delete count)
    BSR.W       TEPASTE_CONT_2                  | adjust lineHeights for paste
    MOVE.W      D7,-(A7)                        | push delete count
    CLR.W       -(A7)                           | push 0 (no replace from buf)
    MOVE.L      D6,-(A7)                        | push insert text ptr
    MOVE.L      D5,-(A7)                        | push insert byte count
    _Munger                                     | replace [selStart,selEnd) with scrap
    ADDQ.L      #0x4,A7                         | drop result long
    MOVEA.L     0x3E(A3),A0                     | A0 = TERec.hText
    _HLock                                      | lock text handle
    SUB.W       D7,0x3C(A3)                     | teLength -= delete count
    ADD.W       D5,0x3C(A3)                     | teLength += insert count
    SUB.W       D5,D7                           | D7 = net delta (negative for growth)
    BSR.W       TE_RECALC_LINES                 | recalc lines
    LEA.L       0x20(A3),A0                     | A0 -> teSelStart
    ADD.W       D5,(A0)                         | teSelStart += insert count
    MOVE.W      (A0)+,(A0)                      | teSelEnd := teSelStart (collapse)
    BSR.W       TE_CARET_RESTORE                | restore caret state
    BSR.W       SelView                         | scroll selection into view
    ADDQ.L      #0x2,A7                         | drop saved styled-flag
    RTS                                         | return from TE_DO_PASTE
| ====================================================================
|
| TE_STYL_PASTE -- styled-paste 'styl' resource handler
|
| Called from TE_DO_PASTE when both teStyleRec is set and the
| caller requested styled paste (TEStylPaste). Fetches the 'styl'
| resource (resType 0x7374796C) from the system scrap, then
| re-keys each style index in the scrap data through TE_LOOKUP_STYLEENTRY
| (find existing matching styleEntry) or TE_APPEND_STYLEENTRY (append new),
| splits boundary runs via TE_SPLIT_STYLERUN_AT, and inserts the result
| into the StyleRec.
|
TE_STYL_PASTE:
    TST.W       0x50(A3)                        | TERec.teStyleRec set ?
    BPL.W       TE_STYL_PASTE_RTS               | no, plain TE -> done
    MOVEM.L     D2-D6/A2/A4,-(A7)               | save scratch regs
    BSR.W       XTRIMMEASURE_CONT_15            | order selection
    MOVE.W      D0,D4                           | D4 = selEnd
    SWAP.W      D0                              | switch to selStart
    MOVEQ.L     #0x0,D3                         | clear D3 high
    MOVE.W      D0,D3                           | D3 = selStart
    MOVEQ.L     #0x0,D0                         | size = 0 (initial alloc)
    BSR.W       TE_RESIZE_AND_DEREF             | allocate temp handle
    MOVEA.L     A0,A4                           | A4 = temp handle
    MOVE.L      A0,-(A7)                        | save for DisposeHandle
    SUBQ.L      #0x4,A7                         | reserve _GetScrap result slot
    MOVEA.L     A7,A1                           | A1 = ptr to result slot
    SUBQ.L      #0x4,A7                         | reserve handle slot
    MOVE.L      A0,-(A7)                        | push destHandle
    MOVE.L      #0x7374796C,-(A7)               | resType = 'styl'
    MOVE.L      A1,-(A7)                        | push offset slot
    _GetScrap                                   | fetch 'styl' from system scrap
    MOVE.L      (A7)+,D0                        | D0 = byte count or err
    ADDQ.L      #0x4,A7                         | drop offset slot
    TST.L       D0                              | got styl data ?
    BPL.B       TE_STYL_PASTE_WALK              | yes, walk it
    BSR.W       TE_PREP_STYLES_FOR_PASTE        | no, just collapse styles
    BRA.W       TE_STYL_PASTE_DISPOSE           | exit
TE_STYL_PASTE_WALK:
    MOVEA.L     A4,A0                           | A0 = temp handle
    _HLock                                      | lock styl data
    MOVE.W      D3,D0                           | D0 = selStart
    MOVE.W      D4,D1                           | D1 = selEnd
    BSR.W       TE_DELETE_STYLES                | collapse selection style runs
    MOVE.W      D3,D0                           | D0 = selStart
    SUBQ.W      #0x1,D0                         | D0 = selStart - 1
    BSR.W       DateToSeconds                   | A0 -> first style run
    MOVE.W      D0,D4                           | D4 = run index
    MOVEA.L     (A4),A4                         | A4 = styl data master ptr
    MOVE.W      (A4),D2                         | D2 = element count from styl header
    LEA.L       0x2(A4),A4                      | A4 -> first styl element (after count)
    MOVE.W      D3,D0                           | D0 = selStart
    BSR.W       TE_SPLIT_STYLERUN_AT            | split run boundary at selStart
    ADD.W       D2,D4                           | D4 = total runs after insertion
    ADDQ.L      #0x4,A0                         | step over inserted entry
    BSR.W       TE_GROW_STYLERUN_ARRAY          | grow styleRun array by D2 entries
    MOVEA.L     A0,A2                           | A2 = output cursor in styleRun array
    MOVEA.L     0x4A(A3),A0                     | A0 = StyleRec handle
    _HLock                                      | lock for in-place edit
| TE_STYL_PASTE_LOOP -- per-styl-element walk
TE_STYL_PASTE_LOOP:
    MOVE.L      (A4),D1                         | D1 = element charPos (relative)
    ADD.L       D3,D1                           | D1 += selStart (absolute)
    CMPI.L      #0xFFFF,D1                      | overflow into byte 4 ?
    BHI.B       TE_STYL_PASTE_NEXT_ELEM         | yes, skip this element
    MOVE.W      D1,-(A7)                        | save absolute charPos
    MOVEA.L     A4,A0                           | A0 -> current styl element
    BSR.W       TE_LOOKUP_STYLEENTRY            | look up matching styleEntry
    TST.L       D0                              | found ?
    BNE.B       TE_STYL_PASTE_USE_INDEX         | yes, use its index
    MOVEA.L     A4,A0                           | no, A0 -> styl element
    ADDQ.L      #0x2,A0                         | skip charPos field
    MOVE.W      #0x1,(A0)                       | refCount = 1
    BSR.W       TE_APPEND_STYLEENTRY            | append new styleEntry
TE_STYL_PASTE_USE_INDEX:
    MOVE.W      (A7)+,D1                        | restore absolute charPos
    MOVE.W      D1,(A2)+                        | styleRun.charPos := D1
    MOVE.W      D0,(A2)+                        | styleRun.styleIndex := D0
TE_STYL_PASTE_NEXT_ELEM:
    ADDA.W      #0x14,A4                        | next styl element (20 bytes each)
    SUBQ.W      #0x1,D2                         | one fewer to process
    BNE.B       TE_STYL_PASTE_LOOP              | continue walk
    SUBQ.W      #0x4,A2                         | back up over terminator
    MOVEA.L     0x4A(A3),A0                     | A0 = StyleRec handle
    _HUnlock                                    | unlock
    MOVEA.L     A2,A0                           | A0 -> last inserted run
    MOVE.W      D4,D0                           | D0 = total runs after insertion
    BSR.W       AdjustRunPositions              | shift follow runs by paste len
    BSR.W       MergeAdjacentRuns               | merge adjacent identical runs
TE_STYL_PASTE_DISPOSE:
    MOVEA.L     (A7)+,A0                        | pop temp handle
    _DisposeHandle                              | discard styl data
    MOVEM.L     (A7)+,D2-D6/A2/A4               | restore scratch
TE_STYL_PASTE_RTS:
    RTS                                         | return from TE_STYL_PASTE
| ----------------------------------------------------------
|
| TE_GROW_STYLERUN_ARRAY -- grow styleRun array by D2 entries (4 bytes each)
|
| A0 -> insertion position. Resizes the styleRun handle to make
| room for D2 new entries past A0, then BlockMoves the trailing
| entries down to make space. A0 returns pointing at the freshly
| opened slot.
|
TE_GROW_STYLERUN_ARRAY:
    MOVEM.L     D2-D3/A2,-(A7)                  | save D2,D3,A2
    MOVEA.L     A0,A2                           | A2 = saved insertion position
    MOVEA.L     0x4A(A3),A0                     | A0 = StyleRec handle
    _HUnlock                                    | unlock for resize
    MOVEA.L     (A0),A1                         | A1 = StyleRec ptr
    MOVEQ.L     #0x1,D0                         | D0 = 1
    ADD.W       (A1),D0                         | D0 = nRuns + 1
    ADD.W       D2,(A1)                         | nRuns += D2
    LSL.L       #0x2,D0                         | * 4 (run size)
    MOVE.L      D0,D3                           | D3 = byte size of run array
    ADDI.L      #0x14,D0                        | + 20 (StyleRec header size)
    LEA.L       0x14(A1),A1                     | A1 -> first run (after header)
    SUBA.L      A1,A2                           | A2 -> offset from run-array start
    SUB.L       A2,D3                           | D3 = bytes after insertion
    EXT.L       D2                              | D2 = insert count (long)
    LSL.L       #0x2,D2                         | * 4 (bytes to insert)
    ADD.L       D2,D0                           | D0 = new total handle size
    BSR.W       TE_RESIZE_TEXTHANDLE            | _SetHandleSize
    MOVEA.L     (A0),A1                         | A1 = new master ptr
    LEA.L       0x14(A1),A1                     | A1 -> first run
    ADDA.L      A2,A1                           | A1 -> insertion position
    _HLock                                      | re-lock
    MOVEA.L     A1,A0                           | A0 = src for shift
    ADDA.L      D2,A1                           | A1 = dst (shifted by D2)
    MOVE.L      D3,D0                           | D0 = bytes to shift
    _BlockMove                                  | shift trailing runs down
    MOVEM.L     (A7)+,D2-D3/A2                  | restore regs
    RTS                                         | return from TE_GROW_STYLERUN_ARRAY
| ----------------------------------------------------------
|
| TE_SPLIT_STYLERUN_AT -- split styleRun at charPos D0
|
| A0 -> styleRun array cursor. If the next run already starts at
| D0, no split needed (TE_SPLIT_STYLERUN_RTS). Otherwise inserts a new run
| at A0+4 with charPos = D0 and styleIndex copied from previous
| run, then bumps the new entry's styleEntry refCount.
|
TE_SPLIT_STYLERUN_AT:
    MOVE.L      D2,-(A7)                        | save D2
    MOVEA.L     A0,A1                           | A1 = previous run ptr
    ADDQ.L      #0x4,A0                         | A0 -> next run
    CMP.W       (A0),D0                         | next run starts at D0 ?
    BEQ.B       TE_SPLIT_STYLERUN_RTS           | yes, no split needed
    MOVE.W      D0,-(A7)                        | save split charPos
    MOVEQ.L     #0x1,D2                         | D2 = 1 entry to insert
    BSR.B       TE_GROW_STYLERUN_ARRAY          | grow array by 1
    MOVEA.L     A0,A1                           | A1 = inserted slot
    SUBQ.W      #0x4,A1                         | A1 = previous run
    MOVE.W      (A7)+,(A0)                      | new entry charPos := split point
    MOVE.W      0x2(A1),D0                      | D0 = previous styleIndex
    MOVE.W      D0,0x2(A0)                      | new entry inherits styleIndex
    BSR.W       GetStyleEntry                   | A0 -> styleEntry for D0
    ADDQ.W      #0x1,(A0)                       | refCount++
TE_SPLIT_STYLERUN_RTS:
    MOVE.L      (A7)+,D2                        | restore D2
    MOVEA.L     A1,A0                           | A0 = previous run (caller convention)
    RTS                                         | return from TE_SPLIT_STYLERUN_AT
| ----------------------------------------------------------
|
| TE_LOOKUP_STYLEENTRY -- look up styleEntry matching A0's input style
|
| Walks the styleEntry array searching for one whose 12-byte
| style portion (offset +6) matches A0+6. If found, increments
| its refCount and returns its 1-based index in D0 (high word
| set so result is non-zero). Returns 0 if not found.
|
TE_LOOKUP_STYLEENTRY:
    MOVE.L      D2,-(A7)                        | save D2
    MOVEA.L     0x4A(A3),A1                     | A1 = StyleRec handle
    MOVEA.L     (A1),A1                         | deref to StyleRec
    MOVE.W      0x2(A1),D2                      | D2 = nStyles (entry count)
    MOVEA.L     0x4(A1),A1                      | A1 = styleEntry handle
    MOVEA.L     (A1),A1                         | deref to entry table
    LEA.L       0x6(A0),A0                      | A0 -> style portion of input
    MOVE.W      D2,D1                           | D1 = countdown loop counter
TE_LOOKUP_STYLEENTRY_LOOP:
    TST.W       (A1)                            | entry refCount > 0 ?
    BEQ.B       TE_LOOKUP_STYLEENTRY_NEXT       | no, skip (free slot)
    BSR.W       TE_CMP_STYLE_BYTES              | compare 12 style bytes
    TST.W       D0                              | match ?
    BEQ.B       TE_LOOKUP_STYLEENTRY_FOUND      | yes, found
TE_LOOKUP_STYLEENTRY_NEXT:
    ADDA.W      #0x12,A1                        | next entry (18 bytes each)
    SUBQ.W      #0x1,D1                         | dec counter
    BNE.B       TE_LOOKUP_STYLEENTRY_LOOP       | continue
    MOVEQ.L     #0x0,D0                         | not found -> D0 = 0
    BRA.B       TE_LOOKUP_STYLEENTRY_RTS        | exit
TE_LOOKUP_STYLEENTRY_FOUND:
    MOVEQ.L     #0x1,D0                         | D0 = 1 (set hi word for non-zero)
    SWAP.W      D0                              | move to hi half
    SUB.W       D1,D2                           | D2 = found index (1-based)
    MOVE.W      D2,D0                           | D0.lo = found index
    ADDQ.W      #0x1,(A1)                       | bump entry refCount
    MOVEA.L     A1,A0                           | A0 -> matched entry
TE_LOOKUP_STYLEENTRY_RTS:
    MOVE.L      (A7)+,D2                        | restore D2
    RTS                                         | return from TE_LOOKUP_STYLEENTRY
| ----------------------------------------------------------
|
| TE_CMP_STYLE_BYTES -- compare 12 style-record bytes for equality
|
| A0 -> input style record, A1 -> existing styleEntry record.
| Compares 12 bytes from A0 against A1+6 (the actual style
| portion, after charPos+styleIndex header). Z set if match.
|
TE_CMP_STYLE_BYTES:
    MOVEM.L     A0-A1,-(A7)                     | save A0,A1
    LEA.L       0x6(A1),A1                      | A1 -> styleEntry style portion
    MOVEQ.L     #0xC,D0                         | D0 = 12 bytes to compare
TE_CMP_STYLE_BYTES_LOOP:
    CMPM.B      (A0)+,(A1)+                     | compare next byte
    BNE.B       TE_CMP_STYLE_BYTES_RTS          | mismatch, stop
    SUBQ.W      #0x1,D0                         | dec count
    BNE.B       TE_CMP_STYLE_BYTES_LOOP         | loop until 0 or mismatch
TE_CMP_STYLE_BYTES_RTS:
    MOVEM.L     (A7)+,A0-A1                     | restore A0,A1
    RTS                                         | return Z = match flag
| ----------------------------------------------------------
|
| TE_APPEND_STYLEENTRY -- append new styleEntry from input at A0
|
| Walks styleEntry table looking for a free slot (refCount = 0).
| If none found, grows the handle by 18 bytes via TE_RESIZE_TEXTHANDLE.
| BlockMoves the 18-byte styleEntry from A0 into the slot.
| Returns D0 = 1-based index of the new entry.
|
TE_APPEND_STYLEENTRY:
    MOVEM.L     D2-D3/A2,-(A7)                  | save D2,D3,A2
    MOVEA.L     0x4A(A3),A1                     | A1 = StyleRec handle
    MOVEA.L     (A1),A2                         | A2 = StyleRec ptr
    MOVE.W      0x2(A2),D0                      | D0 = nStyles (countdown)
    MOVE.W      D0,D3                           | D3 = saved nStyles for index calc
    MOVEA.L     0x4(A2),A1                      | A1 = styleEntry handle
    MOVEA.L     (A1),A1                         | A1 = styleEntry table
TE_APPEND_STYLEENTRY_LOOP:
    TST.W       (A1)                            | refCount == 0 (free slot) ?
    BEQ.B       TE_APPEND_STYLEENTRY_STORE      | yes, use it
    ADDA.W      #0x12,A1                        | next entry (18 bytes)
    SUBQ.W      #0x1,D0                         | dec countdown
    BNE.B       TE_APPEND_STYLEENTRY_LOOP       | continue
| No free slot: grow handle by 18 bytes.
    MOVE.L      A0,-(A7)                        | save input ptr
    ADDQ.W      #0x1,0x2(A2)                    | nStyles++
    MOVEA.L     0x4(A2),A0                      | A0 = styleEntry handle
    _GetHandleSize                              | D0 = current size
    MOVE.L      D0,D2                           | D2 = old size = offset for new entry
    ADDI.L      #0x12,D0                        | D0 += 18
    MOVEA.L     A0,A2                           | A2 = handle
    BSR.W       TE_RESIZE_TEXTHANDLE            | _SetHandleSize
    MOVEA.L     (A7)+,A0                        | restore input ptr
    MOVEA.L     (A2),A1                         | A1 = new master ptr
    ADDA.L      D2,A1                           | A1 -> end of old data (new slot)
    MOVEQ.L     #0x0,D0                         | D0 = 0 (no countdown remaining)
TE_APPEND_STYLEENTRY_STORE:
    SUB.W       D0,D3                           | D3 = found-slot 1-based index
    MOVEQ.L     #0x12,D0                        | D0 = 18 bytes
    _BlockMove                                  | copy input styleEntry into slot
    MOVE.W      D3,D0                           | return D0 = entry index
    MOVEM.L     (A7)+,D2-D3/A2                  | restore regs
    RTS                                         | return from TE_APPEND_STYLEENTRY
| ----------------------------------------------------------
|
| TEPASTE_CONT_2 -- set up _Munger params (text handle + selStart)
|
| Unlocks teText, pushes (resultSlot, hText, selStart, 0L) so the
| caller's RTS into _Munger executes with the right Pascal
| param layout. Used by TEPaste, TEInsert, TEDelete.
|
TEPASTE_CONT_2:
    MOVEA.L     (A7)+,A1                        | A1 = caller's return addr
    MOVEA.L     0x3E(A3),A0                     | A0 = TERec.hText
    _HUnlock                                    | unlock so _Munger can grow it
    SUBQ.L      #0x4,A7                         | reserve _Munger result long
    MOVE.L      A0,-(A7)                        | push hText
    MOVE.W      0x20(A3),-(A7)                  | push teSelStart (offset)
    CLR.W       -(A7)                           | push 0 (no caseFlag)
    CLR.L       -(A7)                           | push nil (no patBuf)
    JMP         (A1)                            | tail-call back to caller
| ----------------------------------------------------------
|
| TE_INSERT_BODY -- _TEInsert text-edit body
|
| D5 = insert byte count, D6 = insert text ptr.  Calls
| TEPASTE_CONT_2 to set up _Munger params, pushes destination
| info, runs _Munger, then HLocks teText again, advances
| teLength, and (for styled TE) rolls forward style-run charPos
| values in the affected range.
|
TE_INSERT_BODY:
    BSR.B       TEPASTE_CONT_2                  | set up _Munger params
    CLR.L       -(A7)                           | matchPtr = nil
    MOVE.L      D6,-(A7)                        | replacePtr = insert text
    MOVE.L      D5,-(A7)                        | replaceLen = insert count
    _Munger                                     | replace at selStart with new text
    ADDQ.L      #0x4,A7                         | drop result long
    MOVEA.L     0x3E(A3),A0                     | A0 = TERec.hText
    _HLock                                      | re-lock for further work
    ADD.W       D5,0x3C(A3)                     | teLength += insert count
    SUB.W       D5,D7                           | D7 -= insert count (net delta)
    TST.W       0x50(A3)                        | TERec.teStyleRec set ?
    BPL.B       TE_INSERT_BODY_RTS              | no, plain TE, done
    MOVE.W      0x20(A3),D0                     | D0 = teSelStart
    SUBQ.W      #0x1,D0                         | D0 = selStart - 1
    BSR.W       DateToSeconds                   | A0 -> first style run >= selStart
    BSR.W       AdjustRunPositions              | shift charPos values by D5
TE_INSERT_BODY_RTS:
    RTS                                         | return from TE_INSERT_BODY
| ----------------------------------------------------------
| _TEInsert ($A9DE) - insert text into TE field at selection.
| Pascal: procedure TEInsert(text: Ptr; length: LongInt;
|                            hTE: TEHandle);
| Hides caret, inserts text via _Munger, recalcs lines, moves
| selection past the inserted text, restores caret state.
| Params at A2: D5 = length, D6 = text ptr.
| ----------------------------------------------------------
TEINSERT:
    BSR.W       TE_PROLOGUE_NODISP              | _TE prologue
    BSR.W       TE_CARET_ERASE                  | hide caret
    BSR.W       TEUPDATE_CONT_2                 | unhighlight selection
    MOVEQ.L     #0x0,D7                         | D7 = 0 (insert mode)
    MOVEM.L     (A2)+,D5-D6                     | D5=length, D6=text ptr
    BSR.B       TE_INSERT_BODY                  | insert via _Munger
    BSR.W       TE_RECALC_LINES                 | recalc lines
    ADD.W       D5,0x20(A3)                     | teSelStart += length
    ADD.W       D5,0x22(A3)                     | teSelEnd += length
    BSR.W       TE_CARET_RESTORE                | restore caret state
    BSR.W       TEUPDATE_CONT_2                 | rehighlight selection
TE_INSERT_EPILOGUE:
    MOVEQ.L     #0xC,D0                         | param size = 12 bytes
    BRA.W       TE_EXIT_4PARAM                  | -> _TE epilogue
| ----------------------------------------------------------
| _TEKey ($A9DC) - process a typed character.
| Pascal: procedure TEKey(key: CHAR; hTE: TEHandle);
| Handles arrows (28-31): move caret without inserting.
| Backspace (8): delete char before selection or selection.
| Otherwise: insert the char via TE_DO_PASTE.
| ----------------------------------------------------------
TEKEY:
    BSR.W       TE_PROLOGUE_NODISP              | _TE prologue
    ST.B        0x47(A3)                        | teLftCaret = true
    _ObscureCursor                              | hide cursor (auto-show on move)
    MOVE.W      (A2),D1                         | D1 = key char
    CMPI.B      #0x8,D1                         | backspace?
    BEQ.B       TEKEY_OK                        | yes -> delete
    MOVEQ.L     #0x1,D2                         | D2 = 1 (forward direction)
    MOVEQ.L     #0x1F,D0                        | D0 = 31
    SUB.B       D1,D0                           | D0 = 31 - key
    BLT.B       TEKEY_NOT_ARROW                 | key > 31 -> printable -> insert
    BEQ.B       TEKEY_VERT_ARROW                | key=31 (right arrow)
    SUBQ.B      #0x1,D0                         | key=30 (up arrow)?
    BEQ.B       TEKEY_UP_ARROW                  | yes -> up (D2=-1, vert mode)
    SUBQ.B      #0x1,D0                         | key=29 (down arrow)?
    BEQ.B       TEKEY_DOWN_ARROW                | yes -> select-end+1
    SUBQ.B      #0x1,D0                         | key=28 (left arrow)?
    BEQ.B       TEKEY_LEFT_ARROW                | yes -> select-start-1
TEKEY_NOT_ARROW:
    BRA.B       TEKEY_INSERT_CHAR               | not arrow -> insert char
TEKEY_UP_ARROW:
    MOVEQ.L     #-0x1,D2                        | up arrow: D2 = -1 (backward)
TEKEY_VERT_ARROW:
    MOVE.W      D2,-(A7)                        | save direction
    MOVE.W      0x20(A3),D3                     | D3 = teSelStart
    MOVE.W      D3,D4                           | D4 = same
    MOVEQ.L     #-0x2,D7                        | D7 = -2 (vert-arrow mode)
    BSR.W       P_doTEDoText                    | get vertical pos info
    MOVE.W      (A7)+,D2                        | restore direction
    BSR.W       TE_LINE_HEIGHT_AT_CHAR          | get line height
    MULS.W      D1,D2                           | scroll = direction * lineHeight
    MOVE.L      0x10(A3),0x1C(A3)               | teSelPoint = teLine.topLeft
    ADD.W       D2,0x1C(A3)                     | adjust v coord by scroll
    BSR.W       TECLICK_CONT_5                  | point -> char offset -> D6
    ST.B        0x47(A3)                        | teLftCaret = true
    BRA.B       TEKEY_SET_SELECTION             | -> set selection
TEKEY_DOWN_ARROW:
    MOVE.W      0x22(A3),D6                     | right arrow: D6 = teSelEnd
    ADDQ.W      #0x1,D6                         | + 1
    BRA.B       TEKEY_SET_SELECTION             | -> set selection
TEKEY_LEFT_ARROW:
    MOVE.W      0x20(A3),D6                     | left arrow: D6 = teSelStart
    BEQ.B       TEKEY_SET_SELECTION             | already at 0 -> stay
    SUBQ.W      #0x1,D6                         | - 1
TEKEY_SET_SELECTION:
    EXT.L       D6                              | sign-extend to long
    MOVE.L      D6,-(A7)                        | push selStart = D6
    MOVE.L      D6,-(A7)                        | push selEnd = D6 (caret)
    MOVE.L      A4,-(A7)                        | push TEHandle
    _TESetSelect                                | move caret
    BSR.W       TE_CARET_SHOW                   | reset blink state
    BRA.B       TEKEY_DONE                      | -> exit
TEKEY_INSERT_CHAR:
    MOVE.L      A2,D6                           | D6 = char ptr (key on stack)
    ADDQ.W      #0x1,D6                         | point past selector word
    MOVEQ.L     #0x1,D5                         | D5 = 1 char to insert
    MOVEQ.L     #0x0,D7                         | D7 = 0 (no styled overhead)
    BSR.W       TE_DO_PASTE                     | insert one char
    BRA.B       TEKEY_DONE                      | -> exit
| ----------------------------------------------------------
| TEKEY_OK - backspace: delete char before selection or
| current selection range.
| ----------------------------------------------------------
TEKEY_OK:
    MOVE.W      0x20(A3),D0                     | D0 = teSelStart
    CMP.W       0x22(A3),D0                     | empty selection?
    BNE.B       TEKEY_CONT                      | no -> delete selection
    TST.W       D0                              | at offset 0?
    BEQ.B       TEKEY_DONE                      | yes -> nothing to delete
    BSR.W       TE_CARET_ERASE                  | hide caret
    SUBQ.W      #0x1,0x20(A3)                   | extend selStart back by 1
TEKEY_CONT:
    MOVE.L      A4,-(A7)                        | push TEHandle
    _TEDelete                                   | delete the selection
| Called by: TEKEY_SET_SELECTION, TEKEY_INSERT_CHAR, TEKEY_OK, TESETJUST, TEAUTOVIEW_EXIT
TEKEY_DONE:
    MOVEQ.L     #0x6,D0                         | param size = 6 (key + handle)
    BRA.W       TE_EXIT_4PARAM                  | -> _TE epilogue
| ----------------------------------------------------------
| TE_PREP_STYLES_FOR_PASTE - prepare style runs for non-styled paste.
| For unstyled TE: just preserves D5.
| For styled TE: collapses adjacent identical style runs in
| the selection range so paste doesn't fragment the StyleRec.
| ----------------------------------------------------------
TE_PREP_STYLES_FOR_PASTE:
    MOVE.W      D5,-(A7)                        | save D5 (paste length)
    TST.W       0x50(A3)                        | styled TE?
    BPL.B       TE_PREP_STYLES_RTS              | no -> done
    BSR.W       XTRIMMEASURE_CONT_15            | order selection
    MOVE.W      D0,D1                           | D1 = selEnd
    SWAP.W      D0                              | D0.W = selStart
    CMP.W       D0,D1                           | empty selection?
    BEQ.B       TE_PREP_STYLES_INSERT_AT        | yes -> skip range collapse
    SUBQ.W      #0x1,D5                         | adjust length for delete
    ADDQ.W      #0x1,D0                         | adjust start for delete
    BSR.W       TE_DELETE_STYLES                | collapse style runs in range
TE_PREP_STYLES_INSERT_AT:
    TST.W       D5                              | any text to insert?
    BEQ.B       TE_PREP_STYLES_RTS              | no -> done
    SUBQ.W      #0x1,D0                         | adjust to insert position
    BSR.W       DateToSeconds                   | locate StyleRec entry
    BSR.W       AdjustRunPositions              | merge with adjacent run
TE_PREP_STYLES_RTS:
    MOVE.W      (A7)+,D5                        | restore D5
    RTS                                         | return from TE_PREP_STYLES_FOR_PASTE
| ----------------------------------------------------------
| TE_LINE_HEIGHT_AT_CHAR - get height of line containing char D3.
| Out: D1 = line height (from TE_CUR_LINE_HEIGHT).
| Saves/restores A2 since TE_ADVANCE_LINESTART/P_TEDOTEXT_CONT_2 modify it.
| ----------------------------------------------------------
TE_LINE_HEIGHT_AT_CHAR:
    MOVE.L      A2,-(A7)                        | save A2
    LEA.L       0x60(A3),A2                     | A2 = teLineStarts
    MOVE.W      D3,D0                           | D0 = char position
    BSR.W       TE_ADVANCE_LINESTART            | locate line for D3
    BSR.W       P_TEDOTEXT_CONT_2               | D0 = line index
    BSR.W       TE_CUR_LINE_HEIGHT              | D1 = line height
    MOVEA.L     (A7)+,A2                        | restore A2
    RTS                                         | return from TE_LINE_HEIGHT_AT_CHAR
| ----------------------------------------------------------
| _TESetJust ($A9DF) - set justification mode.
| Pascal: procedure TESetJust(just: INTEGER; hTE: TEHandle);
| Stores just value in teJust (0x3A).
| ----------------------------------------------------------
TESETJUST:
    BSR.W       TE_PROLOGUE_NODISP              | _TE prologue
    MOVE.W      (A2),0x3A(A3)                   | teJust = param
    BRA.B       TEKEY_DONE                      | -> _TE epilogue
| ----------------------------------------------------------
| TESETALIGNMENT_CONT - redraw text via _TEUpdate of full destRect.
| Used after scrolling. Runs draw mode (D7=-1) on entire
| view, refreshes hilite, restores caret.
| ----------------------------------------------------------
TESETALIGNMENT_CONT:
    MOVEQ.L     #0x0,D3                         | D3 = 0 (draw all)
    MOVEQ.L     #-0x1,D4                        | D4 = -1 (max visible)
    BSR.W       XTRIMMEASURE_CONT_4             | clamp range to viewable lines
    MOVEQ.L     #-0x1,D7                        | D7 = -1 (draw mode)
    BSR.W       P_doTEDoText                    | redraw all visible lines
    BSR.W       TEUPDATE_CONT_2                 | refresh selection hilite
    TST.B       0x38(A3)                        | caret currently shown?
    BEQ.B       TESCROLL_RTS                    | no -> done
    BRA.W       TE_CARET_REDRAW                 | -> redraw caret
| ----------------------------------------------------------
| _TEScroll ($A9DD) - scroll text within view rect.
| Pascal: procedure TEScroll(dh, dv: INTEGER; hTE: TEHandle);
| Hides caret, shifts destRect by (dh,dv), invalidates the
| now-exposed area, redraws.
| Params: D3.W = dh, D3.W high = dv.
| ----------------------------------------------------------
TESCROLL:
    BSR.W       TE_PROLOGUE_NODISP              | _TE prologue
    BSR.W       TE_CARET_ERASE                  | hide caret
    MOVE.L      (A2)+,D3                        | D3 = dh:dv (long)
    BSR.B       TESCROLL_CONT                   | apply scroll
TESCROLL_EPILOGUE:
    MOVEQ.L     #0x8,D0                         | param size = 8 bytes
    BRA.W       TE_EXIT_4PARAM                  | -> _TE epilogue
| ----------------------------------------------------------
| TESCROLL_CONT - apply scroll to text region.
| In: D3 = dh:dv long. Offsets destRect, scrolls bits via
| _ScrollRect, marks exposed area for redraw via TESETALIGNMENT_CONT.
| ----------------------------------------------------------
TESCROLL_CONT:
    TST.L       D3                              | any scroll amount?
    BEQ.B       TESCROLL_RTS                    | no -> nothing to do
    PEA.L       (A3)                            | push destRect
    MOVE.L      D3,-(A7)                        | push dh,dv
    _OffsetRect                                 | shift destRect
    SUBQ.W      #0x4,A7                         | room for new rgn
    _NewRgn                                     | allocate update region
    MOVEA.L     (A7)+,A2                        | A2 = update rgn
    PEA.L       0x8(A3)                         | push viewRect
    MOVE.L      D3,-(A7)                        | push dh,dv
    MOVE.L      A2,-(A7)                        | push update rgn
    _ScrollRect                                 | scroll bits and accumulate update
    BSR.W       TE_REENABLE_BLINK               | re-enable caret blink if needed
    MOVE.L      A2,-(A7)                        | push update rgn
    _SetClip                                    | clip drawing to update area
    MOVEA.L     (A2),A0                         | A0 = update rgn ptr
    LEA.L       0x2(A0),A0                      | A0 = rgn bounds rect
    BSR.B       TESETALIGNMENT_CONT             | redraw exposed area
    MOVE.L      A2,-(A7)                        | push update rgn
    _DisposeRgn                                 | free update rgn
TESCROLL_RTS:
    RTS                                         | return from TESCROLL_CONT
| ----------------------------------------------------------
| TE_REENABLE_BLINK - re-enable caret blink if active and at caret.
| Used after scroll/insert to ensure caret keeps blinking.
| ----------------------------------------------------------
TE_REENABLE_BLINK:
    TST.B       0x24(A3)                        | active?
    BEQ.W       TE_REENABLE_BLINK_EXIT          | no -> done
    MOVE.W      0x20(A3),D0                     | D0 = teSelStart
    CMP.W       0x22(A3),D0                     | == teSelEnd?
    BNE.B       TE_REENABLE_BLINK_EXIT          | no (selection) -> done
    ST.B        0x39(A3)                        | enable caret blink
TE_REENABLE_BLINK_EXIT:
    RTS                                         | return from TE_REENABLE_BLINK
| ----------------------------------------------------------
| _TEPinScroll ($A812) - scroll, pinned to text bounds.
| Pascal: procedure TEPinScroll(dh, dv: INTEGER; hTE: TEHandle);
| Like TEScroll but clamps the scroll so the destRect stays
| within the viewable text. Used by TESelView/TEAutoView.
| Params: D0.W = dv (vertical), D2 = total lines, D1 used.
| ----------------------------------------------------------
TEPINSCROLL:
    BSR.W       TE_PROLOGUE_NODISP              | _TE prologue
    BSR.W       TE_CARET_ERASE                  | hide caret
    MOVE.W      (A2),D0                         | D0 = dv parameter
    BPL.B       PINSCROLL_VPOS                  | dv >= 0 -> scroll up case
    MOVE.W      0x5E(A3),D1                     | D1 = nLines (dv < 0)

    MOVE.W      0x3C(A3),D0                     | D0 = teLength
    TST.W       D0                              | empty TE?
    BEQ.B       PINSCROLL_HEIGHT                | yes -> just compute scroll
    MOVEA.L     0x3E(A3),A0                     | A0 = text handle
    MOVEA.L     (A0),A0                         | A0 = text ptr
    CMPI.B      #0xD,-0x1(A0,D0.W)              | last char is CR?
    BNE.B       PINSCROLL_HEIGHT                | no -> normal
    ADDQ.W      #0x1,D1                         | yes -> count blank line after CR
PINSCROLL_HEIGHT:
    MOVEQ.L     #0x0,D0                         | sum from line 0
    BSR.W       TE_TOTAL_HEIGHT                 | D0 = total height
    MOVE.W      D0,D1                           | D1 = text height
    MOVE.W      (A2),D0                         | D0 = dv
    ADD.W       (A3),D1                         | D1 = destRect.top + height
    SUB.W       0xC(A3),D1                      | D1 = bottom - viewRect.bottom
    BLE.B       PINSCROLL_DV0                   | text fits -> clamp dv
    ADD.W       D1,D0                           | dv = dv + (text - view)
    BPL.B       PINSCROLL_DH                    | dv >= 0 -> ok
    ADD.W       D0,(A2)                         | clamp dv to keep text in view
    BRA.B       PINSCROLL_DH                    | -> dh check
| ----------------------------------------------------------
| PINSCROLL_VPOS - dv positive: clamp to keep destRect.top
| from going below viewRect.top.
| ----------------------------------------------------------
PINSCROLL_VPOS:
    MOVE.W      (A3),D1                         | D1 = destRect.top
    SUB.W       0x8(A3),D1                      | D1 = top - viewRect.top
    BPL.B       PINSCROLL_DV0                   | top >= view top -> ok
    ADD.W       D1,D0                           | dv = dv - (view - top)
    BMI.B       PINSCROLL_DH                    | still negative -> dh check
PINSCROLL_DV0:
    SUB.W       D0,(A2)                         | clamp dv
PINSCROLL_DH:
    MOVE.W      0x2(A2),D0                      | D0 = dh
    BPL.B       PINSCROLL_HPOS                  | dh >= 0 -> positive case
    MOVE.W      0x6(A3),D1                      | D1 = destRect.right
    SUB.W       0xE(A3),D1                      | D1 = right - viewRect.right
    BLE.B       PINSCROLL_DH0                   | text fits -> clamp dh
    ADD.W       D1,D0                           | dh = dh + (text - view)
    BPL.B       PINSCROLL_SCROLL                | dh >= 0 -> ok
    ADD.W       D0,0x2(A2)                      | clamp dh
    BRA.B       PINSCROLL_SCROLL                | -> apply scroll
| ----------------------------------------------------------
| PINSCROLL_HPOS - dh positive: clamp to keep destRect.left
| from going right of viewRect.left.
| ----------------------------------------------------------
PINSCROLL_HPOS:
    MOVE.W      0x2(A3),D1                      | D1 = destRect.left
    SUB.W       0xA(A3),D1                      | D1 = left - viewRect.left
    BPL.B       PINSCROLL_DH0                   | left >= view left -> ok
    ADD.W       D1,D0                           | dh = dh - (view - left)
    BMI.B       PINSCROLL_SCROLL                | still negative -> apply
PINSCROLL_DH0:
    SUB.W       D0,0x2(A2)                      | clamp dh
PINSCROLL_SCROLL:
    MOVE.L      (A2)+,D3                        | D3 = clamped dh:dv
    BSR.W       TESCROLL_CONT                   | apply the scroll
    BSR.W       TE_REENABLE_BLINK               | re-enable caret blink
    BRA.W       TESCROLL_EPILOGUE               | -> _TE epilogue
| ----------------------------------------------------------
| _TESelView ($A811) - scroll selection into view if auto.
| Pascal: procedure TESelView(hTE: TEHandle);
| If teAutoView (bit 6 of 0x42) is set, scrolls the view so
| the selection becomes visible.
| ----------------------------------------------------------
TESELVIEW:
    BSR.W       TE_PROLOGUE_NODISP              | _TE prologue
    BSR.B       SelView                         | scroll selection into view
    BRA.W       TECALTEXT_EXIT                  | -> _TE epilogue
| ----------------------------------------------------------
| SelView - core: pin-scroll selection point into view.
| If autoview is on, computes the selection's pixel location,
| checks if it's in the visible area, and calls _TEPinScroll
| to scroll it into view if not.
| Called by: TESETSELECT, TEDELETE, TE_DO_PASTE_EDIT, TESELVIEW, TESetStyle_Redraw (and 1 more)
| ----------------------------------------------------------
SelView:
    BTST        #0x6,0x42(A3)                   | autoview enabled?
    BEQ.B       SELVIEW_NO_AUTO                 | no -> done
    BSR.W       XTRIMMEASURE_CONT_15            | order selection
    MOVE.W      0x20(A3),D3                     | D3 = teSelStart
    MOVE.W      D3,D4                           | D4 = same
    MOVEQ.L     #-0x2,D7                        | D7 = -2 (locate-mode)
    BSR.W       P_doTEDoText                    | get selection's pixel position
    MOVE.L      0x10(A3),D7                     | D7 = teLine.topLeft
    LEA.L       (OneOne).W,A2                   | A2 = scratch lowmem rect
    LEA.L       0x10(A3),A0                     | A0 = teLine
    MOVE.L      -(A0),-(A2)                     | copy teLine.botRight
    MOVE.L      -(A0),-(A2)                     | copy teLine.topLeft
    MOVE.W      0x20(A3),D3                     | D3 = teSelStart
    BSR.W       TE_LINE_HEIGHT_AT_CHAR          | D1 = line height
    SUB.W       D1,0x4(A2)                      | adjust top by line height
    SUBQ.W      #0x1,0x6(A2)                    | adjust right by 1
    SUBQ.W      #0x2,A7                         | room for _PtInRect result
    MOVE.L      D7,-(A7)                        | push selection point
    MOVE.L      A2,-(A7)                        | push viewRect (computed)
    _PtInRect                                   | selection point in view?
    TST.B       (A7)+                           | result
    BNE.B       SELVIEW_NO_AUTO                 | yes -> no scroll needed
    MOVE.L      (A2)+,-(A7)                     | push topLeft
    MOVE.L      (A2),-(A7)                      | push botRight
    MOVE.L      -(A2),-(A7)                     | push topLeft (again)
    PEA.L       0x4(A7)                         | push botRight ptr
    _SubPt                                      | botRight = topLeft - botRight
    PEA.L       0x4(A7)                         | push topLeft ptr
    _AddPt                                      | midPoint = topLeft + diff/2
    MOVE.L      D7,-(A7)                        | push selection point
    PEA.L       0x4(A7)                         | push midPoint ptr
    _SubPt                                      | scroll = selPoint - midPoint
    MOVE.L      A4,-(A7)                        | push TEHandle
    _TEPinScroll                                | scroll into view (clamped)
SELVIEW_NO_AUTO:
    RTS                                         | return from SelView
| ----------------------------------------------------------
| _TEAutoView ($A813) - enable/disable automatic selection
| scrolling.
| Pascal: procedure TEAutoView(auto: BOOLEAN; hTE: TEHandle);
| Sets bit 6 of teCROnly+1 (0x42 in TERec) based on param.
| ----------------------------------------------------------
TEAUTOVIEW:
    BSR.W       TE_PROLOGUE_NODISP              | _TE prologue
    TST.B       (A2)+                           | auto flag (Boolean param)
    BEQ.B       AUTOVIEW_OFF                    | false -> clear bit
    BSET        #0x6,0x42(A3)                   | true -> set autoview bit
    BRA.B       TEAUTOVIEW_EXIT                 | -> exit
AUTOVIEW_OFF:
    BCLR        #0x6,0x42(A3)                   | clear autoview bit
TEAUTOVIEW_EXIT:
    BRA.W       TEKEY_DONE                      | -> _TE epilogue
| ----------------------------------------------------------
| DefClikProc - default click-loop proc for TEClick.
| Called continuously while user drags. If autoview is on,
| reads current mouse via _GetMouse, computes how far the
| mouse is outside the viewRect, and calls _TEPinScroll to
| auto-scroll text in that direction.
| Called from teClikProc (0x2A(A3)) by TEClick tracking loop.
| ----------------------------------------------------------
DefClikProc:
    MOVEM.L     D0-D7/A0-A4,-(A7)               | save all registers
    BTST        #0x6,0x42(A3)                   | autoview enabled?
    BEQ.B       AUTOSCROLL_NONE                 | no -> return Z (continue)
    LEA.L       0x10(A3),A0                     | A0 = teLine end
    LEA.L       (OneOne).W,A2                   | A2 = scratch lowmem rect
    MOVE.L      -(A0),-(A2)                     | copy teLine.botRight
    MOVE.L      -(A0),-(A2)                     | copy teLine.topLeft
    SUBQ.W      #0x4,A7                         | room for mouse point
    MOVE.L      A7,-(A7)                        | push point ptr
    _GetMouse                                   | read mouse position
    MOVE.W      (A7)+,D6                        | D6 = mouse v
    MOVE.W      (A7)+,D7                        | D7 = mouse h
    MOVEQ.L     #0x0,D4                         | D4 = 0 (h scroll default)
    MOVE.W      0x18(A3),D1                     | D1 = teLineHite
    BPL.B       AUTOSCROLL_CHECK_BOUNDS         | constant lineHite -> use as-is
    MOVE.W      D6,D0                           | D0 = mouse v (styled TE)
    CMP.W       0x4(A3),D0                      | mouse v above destRect.top?
    BLE.B       AUTOSCROLL_GET_LINE             | yes -> use as-is
    MOVE.W      0x4(A3),D0                      | clamp to destRect.top
AUTOSCROLL_GET_LINE:
    BSR.W       TE_PIXELY_TO_LINE               | y -> line index
    BGE.B       AUTOSCROLL_NONE                 | invalid line -> return
    BSR.W       TE_CUR_LINE_HEIGHT              | D1 = line height
AUTOSCROLL_CHECK_BOUNDS:
    CMP.W       (A2)+,D6                        | mouse v above teLine.top?
    BLT.B       AUTOSCROLL_UP                   | yes -> scroll up
    CMP.W       (A2)+,D7                        | mouse h left of teLine.left?
    BLT.B       AUTOSCROLL_LEFT                 | yes -> scroll left
    CMP.W       (A2)+,D6                        | mouse v below teLine.bottom?
    BGT.B       AUTOSCROLL_DOWN                 | yes -> scroll down
    CMP.W       (A2)+,D7                        | mouse h right of teLine.right?
    BGT.B       AUTOSCROLL_RIGHT                | yes -> scroll right
AUTOSCROLL_NONE:
    MOVEQ.L     #0x1,D0                         | D0 = 1 (continue tracking)
    MOVEM.L     (A7)+,D0-D7/A0-A4               | restore registers
    RTS                                         | return Z (mouse inside view)
AUTOSCROLL_DOWN:
    NEG.W       D1                              | scroll down: dv = -lineHite
AUTOSCROLL_UP:
    BRA.B       AUTOSCROLL_APPLY                | scroll up: dv = +lineHite
AUTOSCROLL_RIGHT:
    NEG.W       D1                              | scroll right: dh = -lineHite
AUTOSCROLL_LEFT:
    EXG         D4,D1                           | scroll left: D4=lineHite, D1=0
AUTOSCROLL_APPLY:
    MOVE.W      D4,-(A7)                        | push dv
    MOVE.W      D1,-(A7)                        | push dh
    MOVE.L      0x8(A6),-(A7)                   | push TEHandle (from caller)
    _TEPinScroll                                | scroll one line in direction
    BRA.B       AUTOSCROLL_NONE                 | -> continue tracking
| ----------------------------------------------------------
| DateToSeconds - binary search StyleRec for run containing D0.
| In: D0 = char offset.
| Out: A0 = ptr to entry whose charPos <= D0+1 < next.charPos,
|      D0 = entry index.
| StyleRec layout: (nRuns:W) (elementHandle:L) (lineHeights:L)
|                  (charPos:W ascent:W elementIdx:W)*nRuns
| Called by: TE_PUT_STYL_SCRAP, TE_LOCATE_STYLERUNS, XTRIMMEASURE_PLAIN, TE_DELETE_STYLES, TE_FIND_LINE_BREAK_STYLED (and 5 more)
| ----------------------------------------------------------
DateToSeconds:
    MOVEM.L     D1-D4,-(A7)                     | save scratch
    ADDQ.W      #0x1,D0                         | search for D0+1
    MOVE.W      D0,D2                           | D2 = target
    MOVEA.L     0x4A(A3),A0                     | A0 = StyleRec handle
    MOVEA.L     (A0),A0                         | A0 = StyleRec ptr
    MOVE.W      (A0),D1                         | D1 = nRuns (high bound)
    LEA.L       0x14(A0),A0                     | A0 = first run entry (skip header+lineHeights)
    MOVEQ.L     #0x0,D0                         | D0 = 0 (low bound)
DateToSeconds_LOOP:
    CMP.W       D0,D1                           | low == high?
    BEQ.B       DateToSeconds_AT_ZERO           | yes -> stop
    MOVE.W      D1,D3                           | D3 = high
    ADD.W       D0,D3                           | + low
    LSR.W       #0x1,D3                         | D3 = mid
    MOVEQ.L     #0x0,D4                         | clear D4
    MOVE.W      D3,D4                           | D4 = mid
    LSL.L       #0x2,D4                         | * 4 (entry size)
    CMP.W       0x0(A0,D4.W),D2                 | target vs entry[mid].charPos
    BEQ.B       DateToSeconds_FOUND             | exact match
    BLS.B       DateToSeconds_GO_LOWER          | target <= mid -> upper half
    MOVE.W      D3,D0                           | target > mid -> lower half
    ADDQ.W      #0x1,D0                         | low = mid + 1
    BRA.B       DateToSeconds_LOOP              | continue
DateToSeconds_GO_LOWER:
    MOVE.W      D3,D1                           | high = mid
    BRA.B       DateToSeconds_LOOP              | continue
DateToSeconds_FOUND:
    MOVE.W      D3,D0                           | exact: D0 = mid
DateToSeconds_AT_ZERO:
    TST.W       D0                              | found at index 0?
    BEQ.B       DateToSeconds_RETURN            | yes -> use as-is
    SUBQ.W      #0x1,D0                         | else: use prior entry
DateToSeconds_RETURN:
    MOVEQ.L     #0x0,D1                         | clear D1
    MOVE.W      D0,D1                           | D1 = entry index
    LSL.L       #0x2,D1                         | * 4 (bytes)
    ADDA.L      D1,A0                           | A0 = entry ptr
    MOVEM.L     (A7)+,D1-D4                     | restore scratch
    RTS                                         | return from DateToSeconds
| ----------------------------------------------------------
| CountRunsBefore - count style runs from A0 up to char D1.
| In: A0 = run entry ptr, D1 = end char.
| Out: D0 = number of runs covering range.
| Called by: TE_LOCATE_STYLERUNS, XTRIMMEASURE_PLAIN, TE_PUT_STYL_SCRAP, TE_DELETE_STYLES, TE_FIND_LINE_BREAK_STYLED (and 1 more)
| ----------------------------------------------------------
CountRunsBefore:
    MOVE.L      A0,-(A7)                        | save A0
    MOVEA.L     0x4A(A3),A1                     | A1 = StyleRec handle
    MOVEA.L     (A1),A1                         | A1 = StyleRec ptr
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.W      (A1),D0                         | D0 = nRuns
    LEA.L       0x14(A1),A1                     | A1 = first run entry
    LSL.L       #0x2,D0                         | * 4
    ADDA.L      D0,A1                           | A1 = end of run array
    MOVEQ.L     #0x0,D0                         | D0 = run count
CountRunsBefore_LOOP:
    ADDQ.L      #0x4,A0                         | next run header
    ADDQ.W      #0x1,D0                         | one more run counted
    CMPA.L      A0,A1                           | reached end of runs?
    BEQ.B       CountRunsBefore_DONE            | yes -> done
    CMP.W       (A0),D1                         | D1 > next run's charPos?
    BHI.B       CountRunsBefore_LOOP            | yes -> include and continue
CountRunsBefore_DONE:
    MOVEA.L     (A7)+,A0                        | restore A0
    RTS                                         | return from CountRunsBefore
| ----------------------------------------------------------
| GetStyleEntry - resolve element index to StScrpRec entry.
| In: D0 = element index (font/face/size/color combination).
| Out: A0 = ptr to 18-byte StScrpRec entry.
| Each StScrpRec entry is 18 bytes (size/face/color/font/etc).
| Called by: TECOPY_FIRST_RUN, TE_ADJ_RUNS_LOOP, TE_SPLIT_STYLERUN_AT, TESetStyle_RunLoop, TEContinuousStyle_Entry (and 1 more)
| ----------------------------------------------------------
GetStyleEntry:
    MULU.W      #0x12,D0                        | D0 = index * 18
    MOVEA.L     0x4A(A3),A0                     | A0 = StyleRec handle
    MOVEA.L     (A0),A0                         | A0 = StyleRec ptr
    MOVEA.L     0x4(A0),A0                      | A0 = elementHandle
    MOVEA.L     (A0),A0                         | A0 = element array
    ADDA.L      D0,A0                           | A0 = element[index]
    RTS                                         | return from GetStyleEntry
| ----------------------------------------------------------
| AdjustRunPositions - adjust char positions in StyleRec from A0+4 onward.
| In: A0 = first run entry, D0 = run index, D5 = adjustment.
| Adds D5 to each charPos field in entries from A0+4 to end.
| Used after insert/delete to update style run positions.
| Called by: TE_DELETE_STYLES, TE_DELETE_ADJ_FIRST_RUN, TE_STYL_PASTE_NEXT_ELEM, TE_INSERT_BODY, TE_PREP_STYLES_INSERT_AT
| ----------------------------------------------------------
AdjustRunPositions:
    MOVEA.L     0x4A(A3),A1                     | A1 = StyleRec handle
    MOVEA.L     (A1),A1                         | A1 = StyleRec ptr
    MOVE.W      (A1),D1                         | D1 = nRuns
    SUB.W       D0,D1                           | D1 = remaining runs
    BLS.B       AdjustRunPositions_DONE         | none -> done
AdjustRunPositions_LOOP:
    ADDQ.L      #0x4,A0                         | next run entry
    ADD.W       D5,(A0)                         | charPos += D5
    SUBQ.W      #0x1,D1                         | one less run
    BNE.B       AdjustRunPositions_LOOP         | continue
AdjustRunPositions_DONE:
    RTS                                         | return from AdjustRunPositions
| ====================================================================
|
| _TESetStyle ($A83D) -- apply a TextStyle to the selection
|
| Stack: hTE, mode, newStyle, redraw.  Walks the StyleRec applying
| the requested attribute changes to all style runs that intersect
| the current selection. If redraw flag set (from low byte of
| (A2)+), hides caret + erases selection + re-renders after the
| edit; otherwise just edits style runs in place.
|
| A3 = TERec; teStyleRec at offset 0x50 must be set or this is
| a no-op (plain text). A2 -> trap arguments.
|
TESetStyle_Entry:
    TST.W       0x50(A3)                        | TERec.teStyleRec set ?
    BPL.B       TESetStyle_Exit                 | no, plain text, skip
    MOVE.W      (A2)+,D0                        | D0 = redraw flag word
    ANDI.W      #0xFF00,D0                      | high byte non-zero ?
    BNE.B       TESetStyle_Redraw               | yes, do full hide+edit+show+redraw
    BSR.B       TESetStyle_Frame                | else just edit style runs
    BRA.B       TESetStyle_Exit                 | done
| TESetStyle_Redraw -- redraw path: hide caret, edit, recalc, show, scroll.
TESetStyle_Redraw:
    MOVE.L      A2,-(A7)                        | save trap args ptr
    BSR.W       TE_CARET_ERASE                  | hide caret
    BSR.W       TEUPDATE_CONT_2                 | erase selection
    MOVEA.L     (A7)+,A2                        | restore trap args ptr
    BSR.B       TESetStyle_Frame                | apply style edits
    MOVEQ.L     #0x0,D7                         | D7 = 0 (no growth)
    BSR.W       TE_RECALC_LINES                 | recalc lines after style change
    BSR.W       TE_CARET_RESTORE                | restore caret state
    BSR.W       TEUPDATE_CONT_2                 | re-render selection
    BSR.W       SelView                         | scroll selection into view
TESetStyle_Exit:
    MOVEQ.L     #0xE,D0                         | D0 = 14 bytes of stack params
    BRA.W       TE_EXIT_3PARAM                  | -> common TE epilogue (strip + return)
| ----------------------------------------------------------
|
| TESetStyle_Frame -- TESetStyle dispatch frame
|
| A2 -> [TextStyle ptr (L), mode (W)].  Saves regs, validates
| mode in [0..0x10], and dispatches to TESetStyle_Start (the actual
| style-edit walker).  A4 = TextStyle, D7 = mode bitmask, A6
| (clobbered to 0) is used as a sentinel by the inner loop.
|
TESetStyle_Frame:
    MOVEM.L     D2-D7/A2/A4/A6,-(A7)            | save scratch regs
    MOVEA.L     (A2)+,A4                        | A4 -> TextStyle record
    MOVE.W      (A2)+,D7                        | D7 = style mode bitmask
    SUBA.L      A6,A6                           | A6 = nil (sentinel)
    CMPI.W      #0x10,D7                        | mode > 0x10 (invalid) ?
    BHI.B       TESetStyle_Frame_Exit           | yes, skip
    BSR.B       TESetStyle_Start                | else apply style edit
TESetStyle_Frame_Exit:
    MOVEM.L     (A7)+,D2-D7/A2/A4/A6            | restore regs
    RTS                                         | return from TESetStyle_Frame
| ----------------------------------------------------------
|
| TESetStyle_Start -- TESetStyle inner walker
|
| A4 -> TextStyle, D7 = mode bitmask. Locates the first style run
| at selStart (DateToSeconds) and last run at selEnd (CountRunsBefore).
| Allocates an 18-byte scratch StyleRec template on stack, copies
| TextStyle fields into D3..D7 (packed for inner loop), then HLocks
| the StyleRec handle and walks the affected runs.
|
| TextStyle layout (18 bytes at A4):
|   +0  W  family
|   +2  W  face
|   +4  W  size
|   +6  L  fgColor (RGBColor first long)
|   +A  W  bgColor (top half of RGBColor) - clamped to 0x987 if 0
|
TESetStyle_Start:
    TST.W       D7                              | mode == 0 ?
    BEQ.W       TESetStyle_NoOpRTS              | yes, no-op
    BSR.W       XTRIMMEASURE_CONT_15            | order selection (D0.hi=start, D0.lo=end)
    MOVE.W      D0,D5                           | D5 = selEnd
    MOVE.W      D0,D4                           | D4 = selEnd
    SWAP.W      D0                              | switch to selStart
    MOVE.W      D0,D3                           | D3 = selStart
    SUB.W       D3,D5                           | D5 = selLen
    BEQ.W       TESetStyle_NoOpRTS              | empty selection, no-op
    SUBA.W      #0x12,A7                        | reserve 18 bytes scratch StyleRec
    MOVEA.L     A7,A2                           | A2 -> scratch
    MOVE.W      D3,D0                           | D0 = selStart
    BSR.W       DateToSeconds                   | A0 -> first style run >= selStart
    MOVE.W      D4,D1                           | D1 = selEnd
    BSR.W       CountRunsBefore                 | D0 = run # past selEnd
    MOVE.W      D0,D2                           | D2 = end-run index
    SWAP.W      D3                              | save selStart in D3.hi
    MOVE.W      D4,D3                           | D3.lo = selEnd
    MOVE.W      0x2(A4),D4                      | D4 = TextStyle.face
    SWAP.W      D4                              | save in D4.hi
    MOVE.W      (A4),D4                         | D4.lo = TextStyle.family
    MOVE.W      0x4(A4),D5                      | D5 = TextStyle.size
    MOVE.L      0x6(A4),D6                      | D6 = TextStyle.fgColor (4 bytes)
    SWAP.W      D7                              | save mode in D7.hi
    MOVE.W      0xA(A4),D7                      | D7.lo = TextStyle.bgColor.r
    SWAP.W      D7                              | restore mode in D7.lo, color in D7.hi
    MOVEA.L     A2,A4                           | A4 = scratch StyleRec area
    MOVEA.L     A0,A2                           | A2 -> first style run
    MOVEA.L     0x4A(A3),A0                     | A0 = StyleRec handle
    _HLock                                      | lock for in-place edit
| TESetStyle_RunLoop -- per-run edit loop body
|
| For each style run intersecting the selection:
|   1. Look up its existing styleEntry (GetStyleEntry -> A0)
|   2. Check if requested edit actually changes anything
|      (StyleMatchesTemplate -> D0 = changed-bits mask)
|   3. If changed, copy 18 bytes of existing styleEntry to scratch
|      A4, split run at boundaries (TE_SPLIT_STYLERUN_AT), apply per-mode
|      edits (face, fontFamily/face, size, color, mode, etc.),
|      then look up or create the new styleEntry (TE_LOOKUP_STYLEENTRY /
|      PrimeStyleEntry + TE_APPEND_STYLEENTRY) and update the run's styleIndex.
TESetStyle_RunLoop:
    MOVE.W      0x2(A2),D0                      | D0 = existing styleIndex
    BSR.W       GetStyleEntry                   | A0 -> existing styleEntry
    BSR.W       StyleMatchesTemplate            | D0 = changed-bits mask
    TST.W       D0                              | any change ?
    BEQ.W       TESetStyle_NextRun              | no, next run
    MOVEQ.L     #0x12,D0                        | 18 bytes (sizeof styleEntry)
    MOVEA.L     A4,A1                           | A1 = scratch dst
    _BlockMove                                  | copy current styleEntry to scratch
    MOVEA.L     A2,A0                           | A0 -> current run
    MOVE.L      D3,D0                           | D0 = D3 (selStart in hi)
    SWAP.W      D0                              | D0.lo = selStart
    CMP.W       (A2),D0                         | selStart > run.charPos ?
    BLS.B       TESetStyle_NoStartSplit         | no, no need to split start
    BSR.W       TE_SPLIT_STYLERUN_AT            | yes, insert run boundary at selStart
    ADDQ.W      #0x4,A0                         | step over inserted entry
    MOVEA.L     A0,A2                           | A2 = new current run
TESetStyle_NoStartSplit:
    CMPI.W      #0x1,D2                         | last run in selection ?
    BNE.B       TESetStyle_Apply                | no, skip end-split check
    ADDQ.W      #0x4,A0                         | A0 -> next-run charPos
    CMP.W       (A0),D3                         | selEnd matches next-run start ?
    BEQ.B       TESetStyle_Apply                | yes, no split needed
    MOVE.W      D3,D0                           | D0 = selEnd
    MOVEA.L     A2,A0                           | A0 -> current run
    BSR.W       TE_SPLIT_STYLERUN_AT            | insert run boundary at selEnd
    MOVEA.L     A0,A2                           | A2 = new current run
TESetStyle_Apply:
    MOVEQ.L     #0x1,D0                         | D0 = 1 entry to apply
    MOVEA.L     A2,A0                           | A0 -> current run
    BSR.W       TE_ADJ_RUNS_AFTER_DEL           | walk follow runs (fixup pos)
| Apply per-bit edits to the scratch styleEntry at A4:
| bit 0=family, 1=face, 2=size, 3=color, 4=add-to-size
    BTST        #0x0,D7                         | mode bit 0 (family) ?
    BEQ.B       TESetStyle_FaceCheck            | no
    MOVE.W      D4,0x6(A4)                      | scratch.family := TextStyle.family
TESetStyle_FaceCheck:
    BTST        #0x1,D7                         | mode bit 1 (face) ?
    BEQ.B       TESetStyle_SizeCheck            | no
    MOVE.L      D4,D0                           | D0 = D4 (family in lo, face in hi)
    SWAP.W      D0                              | D0.lo = face
    CMPA.W      #0x0,A6                         | replace mode (A6 = 0) ?
    BEQ.B       TESetStyle_FaceReplace          | yes, special handling
    MOVE.W      D0,0x8(A4)                      | scratch.face := face
    BRA.B       TESetStyle_SizeCheck            | done
TESetStyle_FaceReplace:
    TST.W       D0                              | clearing face ?
    BNE.B       TESetStyle_FaceCleared          | no
    CLR.W       0x8(A4)                         | clear scratch.face
TESetStyle_FaceCleared:
    OR.W        D0,0x8(A4)                      | scratch.face |= face (additive)
TESetStyle_SizeCheck:
    BTST        #0x2,D7                         | mode bit 2 (size) ?
    BEQ.B       TESetStyle_ColorCheck           | no
    BTST        #0x4,D7                         | bit 4 also set (additive) ?
    BNE.B       TESetStyle_ColorCheck           | yes, skip absolute set
    MOVE.W      D5,0xA(A4)                      | scratch.size := TextStyle.size
TESetStyle_ColorCheck:
    BTST        #0x3,D7                         | mode bit 3 (color) ?
    BEQ.B       TESetStyle_AddSize              | no
    MOVE.L      D6,0xC(A4)                      | scratch.color := TextStyle.fgColor
    SWAP.W      D7                              | get bgColor.r from D7.hi
    MOVE.W      D7,0x10(A4)                     | scratch.color.b := bgColor.r
    SWAP.W      D7                              | restore D7.lo (mode bits)
TESetStyle_AddSize:
    BTST        #0x4,D7                         | mode bit 4 (add-to-size) ?
    BEQ.B       TESetStyle_FindOrAddIndex       | no, skip
    MOVE.W      0xA(A4),D0                      | D0 = current size
    BNE.B       TESetStyle_AddSizeDelta         | non-zero, ok
    MOVE.W      #0x987,0xA(A4)                  | else scratch.size := 0x987 (default)
TESetStyle_AddSizeDelta:
    ADD.W       D5,0xA(A4)                      | scratch.size += TextStyle.size (delta)
TESetStyle_FindOrAddIndex:
    MOVEA.L     A4,A0                           | A0 = scratch styleEntry
    BSR.W       TE_LOOKUP_STYLEENTRY            | look up existing matching entry
    TST.L       D0                              | found ?
    BNE.B       TESetStyle_AssignIndex          | yes, use its index
    MOVEA.L     A4,A0                           | no, A0 = scratch
    BSR.W       PrimeStyleEntry                 | install new style fields
    MOVE.W      #0x1,(A0)                       | refCount = 1
    BSR.W       TE_APPEND_STYLEENTRY            | append new styleEntry; D0 = index
TESetStyle_AssignIndex:
    MOVE.W      D0,0x2(A2)                      | run.styleIndex := new index
TESetStyle_NextRun:
    ADDQ.W      #0x4,A2                         | next style run
    SUBQ.W      #0x1,D2                         | one fewer to process
    BNE.W       TESetStyle_RunLoop              | continue loop
    MOVEA.L     0x4A(A3),A0                     | A0 = StyleRec handle
    _HUnlock                                    | done editing
    BSR.W       MergeAdjacentRuns               | merge adjacent identical runs
    ADDA.W      #0x12,A7                        | strip 18-byte scratch
TESetStyle_NoOpRTS:
    RTS                                         | return from TESetStyle_Start
| ----------------------------------------------------------
|
| PrimeStyleEntry -- prime styleEntry with computed font metrics
|
| A0 -> styleEntry being constructed (in scratch). Copies the
| family/face/size fields (offsets +6/+8/+0xA) into the teInPort's
| txFont/txFace/txSize at +0x44/+0x46/+0x4A, calls TE_GET_FONT_INFO to
| measure font, then writes ascent (D0) at +4 and lineHeight (D1)
| at +2 of the styleEntry.
|
PrimeStyleEntry:
    MOVE.L      D2,-(A7)                        | save D2
    MOVEA.L     0x52(A3),A1                     | A1 = teInPort
    MOVE.W      0x6(A0),0x44(A1)                | port.txFont := styleEntry.family
    MOVE.W      0x8(A0),0x46(A1)                | port.txFace := styleEntry.face
    MOVE.W      0xA(A0),0x4A(A1)                | port.txSize := styleEntry.size
    BSR.W       TE_GET_FONT_INFO                | measure: D1 = lineHeight, D0 = ascent
    MOVE.W      D0,0x4(A0)                      | styleEntry.ascent := D0
    MOVE.W      D1,0x2(A0)                      | styleEntry.lineHeight := D1
    MOVE.L      (A7)+,D2                        | restore D2
    RTS                                         | return from PrimeStyleEntry
| ====================================================================
|
| _TEContinuousStyle ($A83A) -- query continuous style at selection
|
| Stack: hTE, var mode (W), var TextStyle (18 bytes).
| For styled TE: looks up the style at selStart and writes its
| family/face/size/color into caller's TextStyle var. Caller's
| mode word is consumed but not used for filtering here; instead
| the entire style is returned.
| For unstyled TE: uses the teInPort's txFont/Face/Size and
| computes the corresponding pen-mode pattern via BuildHilitePattern.
|
TEContinuousStyle_Entry:
    TST.W       0x50(A3)                        | TERec.teStyleRec set ?
    BPL.B       TEContinuousStyle_PlainPath     | no, plain text path
    MOVE.L      (A2)+,-(A7)                     | save TextStyle ptr (1)
    MOVE.L      (A2)+,-(A7)                     | save mode var ptr (2)
    MOVE.L      (A2)+,-(A7)                     | save txMode dst ptr (3)
    MOVE.W      (A2),D0                         | D0 = current selStart
    BSR.W       DateToSeconds                   | A0 -> first style run
    MOVE.W      0x2(A0),D0                      | D0 = run.styleIndex
    BSR.W       GetStyleEntry                   | A0 -> styleEntry for D0
    MOVEA.L     (A7)+,A1                        | A1 = caller's TextStyle ptr
    MOVE.W      0x6(A0),(A1)+                   | dst.family := styleEntry.family
    MOVE.W      0x8(A0),(A1)+                   | dst.face   := styleEntry.face
    MOVE.W      0xA(A0),(A1)+                   | dst.size   := styleEntry.size
    MOVEA.L     A0,A2                           | A2 = saved styleEntry ptr
    LEA.L       0xC(A0),A0                      | A0 -> styleEntry color (3 words)
    MOVE.W      (A0)+,(A1)+                     | dst.color.r
    MOVE.W      (A0)+,(A1)+                     | dst.color.g
    MOVE.W      (A0),(A1)                       | dst.color.b
    MOVEA.L     (A7)+,A1                        | A1 = caller's mode var ptr
    MOVE.W      0x2(A2),(A1)                    | mode := styleEntry.lineHeight (?)
    MOVEA.L     (A7)+,A1                        | A1 = caller's txMode dst ptr
    MOVE.W      0x4(A2),(A1)                    | dst := styleEntry.ascent (?)
    BRA.B       TEContinuousStyle_Exit          | -> exit
| TEContinuousStyle_PlainPath -- plain TE: synthesize TextStyle from teInPort
TEContinuousStyle_PlainPath:
    BSR.W       TE_GET_FONT_INFO                | D0/D1 = lineHeight, ascent
    MOVEA.L     (A2)+,A0                        | A0 = caller's mode dst
    MOVE.W      D0,(A0)                         | mode := lineHeight
    MOVEA.L     (A2)+,A0                        | A0 = caller's ascent dst
    MOVE.W      D1,(A0)                         | ascent := D1
    MOVEA.L     (A2),A0                         | A0 = caller's TextStyle ptr
    MOVEA.L     0x52(A3),A1                     | A1 = teInPort
    MOVE.W      0x44(A1),(A0)+                  | dst.family := port.txFont
    MOVE.W      0x46(A1),(A0)+                  | dst.face   := port.txFace
    MOVE.W      0x4A(A1),(A0)+                  | dst.size   := port.txSize
    PEA.L       (A0)                            | push pattern dst ptr
    BSR.W       BuildHilitePattern              | install pen-mode pattern
TEContinuousStyle_Exit:
    MOVEQ.L     #0x14,D0                        | D0 = 20 bytes of stack params
    BRA.W       TE_EXIT_3PARAM                  | -> common TE epilogue
| ----------------------------------------------------------
|
| SetPortFromStyleRun -- pack styleEntry to TextStyle + emit pen-mode
|
| A0 -> styleRun. Looks up its styleEntry, copies its font
| metrics into teInPort, then emits pen-mode pattern via
| PackTexturePattern using the styleEntry.color (offset 0xC).
|
| Called by: PIXELTOCHAR_STY_RUN_LOOP, TEDOTEXT_DRAW_RUN, TEDELETE_CONT_2, XTRIMMEASURE_RUN_LOOP, TE_MEASURE_RUN (and 1 more)
SetPortFromStyleRun:
    MOVE.L      A0,-(A7)                        | save A0 (styleRun)
    MOVE.W      0x2(A0),D0                      | D0 = styleRun.styleIndex
    BSR.W       GetStyleEntry                   | A0 -> styleEntry for D0
    MOVEA.L     0x52(A3),A1                     | A1 = teInPort
    MOVE.W      0x6(A0),0x44(A1)                | port.txFont := styleEntry.family
    MOVE.W      0x8(A0),0x46(A1)                | port.txFace := styleEntry.face
    MOVE.W      0xA(A0),0x4A(A1)                | port.txSize := styleEntry.size
    PEA.L       0xC(A0)                         | push styleEntry.color ptr
    BSR.W       PackTexturePattern              | install pen-mode pattern from color
    MOVEA.L     (A7)+,A0                        | restore A0
    RTS                                         | return from SetPortFromStyleRun
| ----------------------------------------------------------
|
| MergeAdjacentRuns -- merge adjacent styleRuns with identical styleIndex
|
| Walks the styleRun array compacting adjacent runs that share a
| styleIndex. For each removed run, decrements that styleIndex's
| styleEntry refCount. Updates StyleRec.nRuns at the end.
|
MergeAdjacentRuns:
    MOVEM.L     D2/A2,-(A7)                     | save D2,A2
    MOVEA.L     0x4A(A3),A0                     | A0 = StyleRec handle
    MOVEA.L     (A0),A0                         | deref to StyleRec
    MOVEA.L     0x4(A0),A2                      | A2 = styleEntry handle
    MOVEA.L     (A2),A2                         | A2 = styleEntry table
    MOVE.W      (A0),D0                         | D0 = nRuns
    ADDQ.W      #0x1,D0                         | + 1 (terminator)
    LEA.L       0x14(A0),A0                     | A0 -> first styleRun (compact dst)
    MOVEA.L     A0,A1                           | A1 = scan src cursor
    MOVEQ.L     #0x0,D2                         | D2 = removal count
    MOVE.W      0x2(A0),D1                      | D1 = current styleIndex
MergeAdjacentRuns_LOOP:
    SUBQ.W      #0x1,D0                         | one fewer run to scan
    BEQ.B       MergeAdjacentRuns_DONE          | done
    ADDQ.W      #0x1,D2                         | bump removal count tentatively
    ADDQ.L      #0x4,A1                         | next src run
    CMP.W       0x2(A1),D1                      | same styleIndex ?
    BEQ.B       MergeAdjacentRuns_LOOP          | yes, skip (merge)
    SUBQ.W      #0x1,D2                         | adjust (one too many counted)
    BEQ.B       MergeAdjacentRuns_COPY          | no merges happened, just copy
    MULU.W      #0x12,D1                        | D1 = styleIndex * 18
    SUB.W       D2,0x0(A2,D1.L)                 | refCount -= merged count
    MOVEQ.L     #0x0,D2                         | reset removal counter
MergeAdjacentRuns_COPY:
    ADDQ.L      #0x4,A0                         | next dst run
    MOVE.L      (A1),(A0)                       | copy run to dst
    MOVE.W      0x2(A0),D1                      | D1 = next styleIndex
    BRA.B       MergeAdjacentRuns_LOOP          | continue scan
MergeAdjacentRuns_DONE:
    SUBA.L      A0,A1                           | A1 = bytes removed
    MOVE.L      A1,D0                           | D0 = bytes removed
    MOVEA.L     0x4A(A3),A0                     | A0 = StyleRec handle
    MOVEA.L     (A0),A1                         | A1 = StyleRec ptr
    ASR.L       #0x2,D0                         | D0 = entries removed
    SUB.W       D0,(A1)                         | nRuns -= removed
    MOVEM.L     (A7)+,D2/A2                     | restore regs
    RTS                                         | return from MergeAdjacentRuns
| ----------------------------------------------------------
|
| StyleMatchesTemplate -- decide whether to apply edit to current style run
|
| A0 -> existing styleEntry, A6 -> conditional-match template
| (nil to force always-apply), D7 = mode bitmask.
|
| Returns D0:
|   1 = apply edit (A6 nil OR existing matches A6 template)
|   0 = skip       (any field selected by D7 differs from A6)
|
| The conditional match lets _TEReplaceStyle change only those
| runs whose existing style matches a caller-supplied template.
|
| Mode bits map to styleEntry fields:
|   0 = family (+6)
|   1 = face   (+8)
|   2 = size   (+0xA)
|   3 = color  (+0xC fgColor + +0x10 bgColor.r)
|
StyleMatchesTemplate:
    MOVEQ.L     #0x1,D0                         | D0 = 1 (apply edit)
    CMPA.W      #0x0,A6                         | match-template provided ?
    BEQ.B       StyleMatchesTemplate_RTS        | no, force apply (return 1)
    BTST        #0x0,D7                         | check family ?
    BEQ.B       StyleMatchesTemplate_FaceCheck  | not requested, skip check
    MOVE.W      (A6),D1                         | D1 = template.family
    CMP.W       0x6(A0),D1                      | matches existing ?
    BNE.B       StyleMatchesTemplate_No         | no, skip (D0 = 0)
StyleMatchesTemplate_FaceCheck:
    BTST        #0x1,D7                         | check face ?
    BEQ.B       StyleMatchesTemplate_SizeCheck  | not requested
    MOVE.W      0x2(A6),D1                      | D1 = template.face
    CMP.W       0x8(A0),D1                      | matches ?
    BNE.B       StyleMatchesTemplate_No         | no, skip
StyleMatchesTemplate_SizeCheck:
    BTST        #0x2,D7                         | check size ?
    BEQ.B       StyleMatchesTemplate_ColorCheck | not requested
    MOVE.W      0x4(A6),D1                      | D1 = template.size
    CMP.W       0xA(A0),D1                      | matches ?
    BNE.B       StyleMatchesTemplate_No         | no, skip
StyleMatchesTemplate_ColorCheck:
    BTST        #0x3,D7                         | check color ?
    BEQ.B       StyleMatchesTemplate_RTS        | not requested, apply
    MOVE.L      0x6(A6),D1                      | D1 = template fgColor (4 bytes)
    CMP.L       0xC(A0),D1                      | matches ?
    BNE.B       StyleMatchesTemplate_No         | no, skip
    MOVE.W      0xA(A6),D1                      | D1 = template bgColor.r
    CMP.W       0x10(A0),D1                     | matches ?
    BEQ.B       StyleMatchesTemplate_RTS        | yes, apply (D0 = 1)
StyleMatchesTemplate_No:
    MOVEQ.L     #0x0,D0                         | mismatch -> skip
StyleMatchesTemplate_RTS:
    RTS                                         | return D0
| ----------------------------------------------------------
|
| _TEReplaceStyle ($A83E) -- conditionally apply style edits
|
| Like TESetStyle but only edits runs whose existing style
| matches a caller-supplied template (via StyleMatchesTemplate). Stack
| has TextStyle ptr, MatchTemplate ptr, mode word, redraw flag.
| For empty redraw (high byte of mode word = 0), edit in place.
| Otherwise hide caret + erase + edit + recalc + show.
|
TEReplaceStyle_Entry:
    TST.W       0x50(A3)                        | TERec.teStyleRec set ?
    BPL.B       TEReplaceStyle_Exit             | no, plain text, skip
    MOVE.W      (A2)+,D0                        | D0 = redraw flag word
    ANDI.W      #0xFF00,D0                      | high byte non-zero ?
    BNE.B       TEReplaceStyle_Redraw           | yes, full hide+edit+show
    BSR.B       TEReplaceStyle_Frame            | else just edit in place
    BRA.B       TEReplaceStyle_Exit             | done
| TEReplaceStyle_Redraw redraw path: hide caret, edit, recalc, show, scroll.
TEReplaceStyle_Redraw:
    MOVE.L      A2,-(A7)                        | save trap args ptr
    BSR.W       TE_CARET_ERASE                  | hide caret
    BSR.W       TEUPDATE_CONT_2                 | erase selection
    MOVEA.L     (A7)+,A2                        | restore args ptr
    BSR.B       TEReplaceStyle_Frame            | apply style edits
    MOVEQ.L     #0x0,D7                         | D7 = 0 (no growth)
    BSR.W       TE_RECALC_LINES                 | recalc lines
    BSR.W       TE_CARET_RESTORE                | restore caret
    BSR.W       TEUPDATE_CONT_2                 | re-render selection
    BSR.W       SelView                         | scroll selection into view
TEReplaceStyle_Exit:
    MOVEQ.L     #0x12,D0                        | D0 = 18 bytes of stack params
    BRA.W       TE_EXIT_3PARAM                  | -> common TE epilogue
| ----------------------------------------------------------
|
| TEReplaceStyle_Frame -- TEReplaceStyle dispatch frame
|
| A2 -> [TextStyle (L), MatchTemplate (L), mode (W)].
| Saves regs and sets up A4 = TextStyle, A6 = MatchTemplate
| (the conditional template used by StyleMatchesTemplate), D7 = mode
| bitmask. Validates mode in [0..0x10] and dispatches to the
| shared TESetStyle_Start walker.
|
TEReplaceStyle_Frame:
    MOVEM.L     D2-D7/A2/A4/A6,-(A7)            | save scratch regs
    MOVEA.L     (A2)+,A4                        | A4 -> TextStyle to apply
    MOVEA.L     (A2)+,A6                        | A6 -> MatchTemplate (StyleMatchesTemplate)
    MOVE.W      (A2)+,D7                        | D7 = mode bitmask
    CMPI.W      #0x10,D7                        | mode > 0x10 (invalid) ?
    BCC.B       TEReplaceStyle_Frame_Exit       | yes, skip
    BSR.W       TESetStyle_Start                | else apply via shared walker
TEReplaceStyle_Frame_Exit:
    MOVEM.L     (A7)+,D2-D7/A2/A4/A6            | restore regs
    RTS                                         | return from TEReplaceStyle_Frame
| ----------------------------------------------------------
|
| _TEGetOffset ($A83A) -- pixel position to char offset
|
| Stack: hTE, point, var offset.  Sets teSelPoint (0x1C) to the
| supplied point, calls TECLICK_CONT_5 which fills D6 with the char
| offset under the point, then writes D6 to the var slot and
| restores teSelPoint.
|
TEGETOFFSET:
    BSR.W       TE_PROLOGUE_NODISP              | _TE prologue
    MOVE.L      0x1C(A3),-(A7)                  | save existing teSelPoint
    MOVE.L      (A2)+,0x1C(A3)                  | teSelPoint := caller's point
    BSR.W       TECLICK_CONT_5                  | D6 = char offset under point
    MOVE.W      D6,(A2)                         | write to var offset slot
    MOVE.L      (A7)+,0x1C(A3)                  | restore old teSelPoint
    BRA.W       TESCROLL_EPILOGUE               | -> _TE epilogue (8-byte strip)
| ----------------------------------------------------------
|
| _TEGetStyleHandle ($A839) -- get StyleRec handle
|
| Returns TERec.teStyleRec (offset 0x4A, the StyleHandle) on
| stack, or nil if TE is unstyled (teStyleRec offset 0x50 >= 0).
|
TEGetStyleHandle_Entry:
    CLR.L       (A2)                            | result := nil (default)
    TST.W       0x50(A3)                        | teStyleRec set ?
    BPL.B       TEGetStyleHandle_Exit           | no, leave nil
    MOVE.L      0x4A(A3),(A2)                   | yes, return StyleHandle
TEGetStyleHandle_Exit:
    MOVEQ.L     #0x6,D0                         | D0 = 6 bytes of params
    BRA.W       TE_EXIT_3PARAM                  | -> common TE epilogue
| ----------------------------------------------------------
|
| _TESetStyleHandle ($A83B) -- install caller-supplied StyleRec
|
| Stack: hTE, newStyleHandle.  No-op if TE is unstyled.
|
TESetStyleHandle_Entry:
    TST.W       0x50(A3)                        | teStyleRec set ?
    BPL.B       TESetStyleHandle_Exit           | no, just return
    MOVE.L      (A2),0x4A(A3)                   | install new StyleHandle
TESetStyleHandle_Exit:
    MOVEQ.L     #0xA,D0                         | D0 = 10 bytes of params
    BRA.W       TE_EXIT_3PARAM                  | -> common TE epilogue
| ----------------------------------------------------------
|
| PackTexturePattern -- pack 3-word texture pattern + write to GrafPort
|
| A7+4 -> 6-byte input array of three words (3 bits each).
| Packs them into D1 by shifting left 1 bit each, then uses D1
| as an 8-bit table index into PenModePatternTbl (16 longs of canned
| pen-mode patterns).  Writes the resulting long into GrafPort.
| pnMode field at offset 0x50.
|
| Used by _TEStylNew during port style setup.
|
PackTexturePattern:
    MOVEA.L     0x4(A7),A1                      | A1 -> input 6-byte array
    MOVEQ.L     #0x0,D1                         | D1 = 0
    MOVE.W      (A1)+,D1                        | D1 = bit0 from word 0
    LSL.L       #0x1,D1                         | shift left
    MOVE.W      (A1)+,D1                        | D1 |= bit from word 1
    LSL.L       #0x1,D1                         | shift left
    MOVE.W      (A1)+,D1                        | D1 |= bit from word 2
    LSL.L       #0x1,D1                         | shift left
    SWAP.W      D1                              | move into high half
    LEA.L       PenModePatternTbl(PC),A0        | A0 -> pattern table
    MOVEQ.L     #0x0,D0                         | clear D0
    LSL.W       #0x1,D1                         | scale to long-stride index
    MOVE.W      0x0(A0,D1.W),D0                 | D0 = packed pattern long
    MOVEA.L     (A5),A0                         | A0 = QD globals handle
    MOVEA.L     (A0),A0                         | A0 = current GrafPort
    MOVE.L      D0,0x50(A0)                     | port.pnMode := D0
    MOVEA.L     (A7)+,A0                        | A0 = return addr
    ADDQ.W      #0x4,A7                         | strip param ptr
    JMP         (A0)                            | tail-call return from PackTexturePattern via A0
| Lookup table for PackTexturePattern: 8 longs (16 word indices) used
| as canned pen-mode patterns indexed by packed input bits.
PenModePatternTbl:
    .long       0x00210199                      | indices 0,1
    .long       0x01550111                      | indices 2,3
    .long       0x00CD0089                      | indices 4,5
    .long       0x0045001E                      | indices 6,7
| ----------------------------------------------------------
| BuildHilitePattern - install txMode-derived ASCII pattern at *(A7+4).
| Used by TextEdit setup (TE_PROLOGUE_NODISP) to build a 6-byte glyph
| substitution pattern from the GrafPort's source-mode bits
| (port.pnPat fragment): bit-tests through the mode word and
| writes 0x0000 (clear) or 0xFFFF (filled) into 3 successive
| words, providing a fast XOR-mode hilite stencil.
| ----------------------------------------------------------
BuildHilitePattern:
    MOVEA.L     0x4(A7),A1                      | A1 = pattern dest (caller's buf)
    MOVEA.L     (A5),A0                         | A0 = QD globals handle
    MOVEA.L     (A0),A0                         | A0 = current GrafPort
    MOVE.L      0x50(A0),D0                     | D0 = port pnMode field
    BTST        #0x5,D0                         | source-mode bit 5 set?
    BEQ.B       BuildHilitePattern_Align        | no -> use as-is
    ORI.W       #0x1C0,D0                       | OR in modifier bits
BuildHilitePattern_Align:
    LSR.W       #0x1,D0                         | shift to align stencil
    MOVEQ.L     #0x2,D1                         | 3 words to write
BuildHilitePattern_LOOP:
    CLR.W       (A1)                            | default = $0000
    LSL.B       #0x1,D0                         | shift next bit to carry
    BCS.B       BuildHilitePattern_LeaveZero    | bit set -> leave as $0000
    NOT.W       (A1)                            | bit clear -> $FFFF (filled)
BuildHilitePattern_LeaveZero:
    ADDQ.W      #0x2,A1                         | next word slot
    DBF.W       D1,BuildHilitePattern_LOOP      | loop 3 times
    MOVEA.L     (A7)+,A0                        | A0 = return addr
    ADDQ.W      #0x4,A7                         | strip param ptr
    JMP         (A0)                            | tail-call return from BuildHilitePattern_LeaveZero via A0
