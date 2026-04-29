| System Error -- DS Alert Rendering and Mouse-Button Tracking
|
| Called from the DS error handler (classic: in boot/sad_mac.s tail;
| Plus: in debugger/debugger.s) after the alert's shape and contents
| have been determined. This file renders the alert frame, draws the
| text, lays out buttons, and tracks mouse-button clicks to dismiss
| or accept the alert.
|
| Classic 1984 context: this IS the entire "built-in debugger" -- just
| a simple DS alert renderer. The full MacsBug-style debugger seen in
| Plus (MicroBug, hex-command expression parser) does not exist in
| classic.
|
| Routines:
| DRAW_ALERT_TEXT - parse '/'-separated text and draw each line.
| DRAWTEXT_SCAN / DRAWTEXT_SEGMENT / DRAWTEXT_DONE - text rendering.
| DRAW_ALERT_FRAME / DT_ALERT_RECT - alert frame rectangle
| (Plus has equivalent DRAW_ALERT_FRAME but inlines
| the rect in SET_DEFAULT_RECT).
| SHOW_ALERT_BTNS / DRAW_BTN_LOOP - draw OK/Cancel-style buttons.
| WAIT_MOUSE_DOWN - block until a click.
| HITTEST_BTN_LOOP / TRACK_BTN_* - track mouse-down across buttons.
| BTN_PT_IN_RECT / BTN_INVERT - point-in-rect + button-highlight helpers.
|
| References: Inside Macintosh Vol II, Ch 12 (System Error Handler);
| Technical Note TN1136 (built-in debugger overview).

| ----------------------------------------------------------
|
| DRAW_ALERT_TEXT - draw text string from alert table entry
|
| Reads text ID from A3, looks it up in the alert table,
| then draws the text at position D3. Text is split on '/'
| (0x2F) into multiple lines, advancing Y by 14 pixels each line.
DRAW_ALERT_TEXT:
        MOVE    (A3)+,D0                        | text resource ID from alert def
        BEQ.B   DRAWTEXT_DONE                   | 0 = no text, skip
        BSR.B   LOOKUP_ALERT_ID                 | look up text ID in alert table
        BEQ.B   DRAWTEXT_DONE                   | not found - skip
        MOVE.L  (A0)+,D3                        | D3 = drawing position (v.h packed)
        MOVE.L  A0,A2                           | A2 = start of text string
DRAWTEXT_SCAN:
        MOVE.B  (A0)+,D0                        | read next character
        BEQ.B   DRAWTEXT_SEGMENT                | null terminator - draw final segment
        CMPI.B  #0x2F,D0                        | '/' = line break delimiter?
        BNE.B   DRAWTEXT_SCAN                   | no - keep scanning
DRAWTEXT_SEGMENT:
        MOVE.B  D0,-(SP)                        | save terminator/delimiter on stack
        MOVE.L  A2,-(SP)                        | push text base ptr for DrawText
        CLR     -(SP)                           | push firstByte = 0
        MOVE.L  A0,D0                           | compute string segment length
        SUB.L   A2,D0                           | D0 = chars scanned
        SUBQ.W  #0x1,D0                         | exclude terminator byte
        MOVE.L  A0,A2                           | advance A2 to next segment
        MOVE    D0,-(SP)                        | push byteCount for DrawText
        MOVE.L  D3,-(SP)                        | push pen position (v.h)
        _MoveTo                                 | set pen to text position
        _DrawText                               | draw the text segment
        ADDI.L  #0xE0000,D3                     | advance Y by 14 pixels (0xE << 16)
        MOVE.L  A2,A0                           | A0 = start of next segment
        MOVE.B  (SP)+,D0                        | restore terminator
        BNE.B   DRAWTEXT_SCAN                   | not null - more segments to draw
DRAWTEXT_DONE:
        RTS                                     | return from text drawing
| ----------------------------------------------------------
| DRAW_ALERT_FRAME -- draw the dialog-frame rectangle and shadow
| Called by SysError after InitPort. A2 ends up pointing at
| the DT_ALERT_RECT inline Rect data (top,left,bottom,right).
DRAW_ALERT_FRAME:                               | draw frame
        LEA     DT_ALERT_RECT(PC),A2            | A2 = ptr to inline Rect
        MOVE.L  A2,-(SP)                        | push &rect
        _EraseRect                              | clear the dialog background
        MOVE.L  A2,-(SP)                        | push &rect
        _FrameRect                              | draw 1-pixel border
        MOVE.L  #0x00030003,-(SP)               | pen size = 3 x 3
        _PenSize                                | set pen thickness
        MOVE    0x2(A2),-(SP)                   | push rect.left (shadow h-start)
        ADDQ.W  #0x3,(SP)                       | +3 pixel offset for shadow
        MOVE    0x4(A2),-(SP)                   | push rect.bottom (shadow v)
        _MoveTo                                 | pen to (left+3, bottom)
        MOVE    0x6(A2),-(SP)                   | push rect.right (h for both LineTos)
        MOVE    (SP),-(SP)                      | duplicate rect.right (2nd LineTo h)
        MOVE    0x4(A2),-(SP)                   | push rect.bottom (1st LineTo v)
        _LineTo                                 | draw bottom horizontal shadow (down to right-bottom)
        MOVE    (A2),-(SP)                      | push rect.top (2nd LineTo v)
        ADDQ.W  #0x3,(SP)                       | start 3 pixels below top (matches shadow inset)
        _LineTo                                 | draw right-edge vertical shadow (up to top+3)
        _PenNormal                              | restore 1x1 pen
DRAW_ALERT_FRAME_EXIT:
        RTS                                     | frame complete
| ----------------------------------------------------------
| DT_ALERT_RECT -- 8-byte dialog-frame Rect, consumed by a
| PC-relative PEA from DRAW_ALERT_FRAME above. Rect format:
| top, left, bottom, right = (64, 32, 190, 480) -- centred error pane.
DT_ALERT_RECT:                                  | dialog Rect (8 bytes)
        .short  0x0040, 0x0020                  | top=64, left=32
        .short  0x00BE, 0x01E0                  | bottom=190, right=480
| ----------------------------------------------------------
| SHOW_ALERT_BTNS -- draw buttons + enter click-loop
| On entry: D0 = button-defn resource ID, A5 = QD globals.
| Fetches the button table (count + N x 12-byte button defs), draws
| each button with its label + frame, then polls mouse until click
| lands in a button rect and that button is released.
SHOW_ALERT_BTNS:                                | BUTTONS_DRAW
        BSR.W   LOOKUP_ALERT_ID                 | look up button-table resource
        BEQ.B   DRAW_ALERT_FRAME_EXIT           | not found -> return (nothing to draw)
        MOVEA.L A0,A2                           | save button-table base
        MOVE    (A0)+,D3                        | D3 = button count
        MOVE.L  A0,A3                           | A3 = first button definition
DRAW_BTN_LOOP:                                  | draw one button
        MOVE.L  2(A3),-(SP)                     | push button rect topLeft
        ADDI.L  #0x000E0004,(SP)                | +14 Y (baseline) / +4 X (indent)
        _MoveTo                                 | position pen for button label
        MOVE    (A3),D0                         | D0 = button label text ID
        BSR.W   LOOKUP_ALERT_ID                 | look up text in alert table
        SUBQ.W  #0x1,A0                         | back up to include length byte
        MOVE.L  A0,-(SP)                        | push pascal string ptr
        _DrawString                             | draw button label text
        PEA.L     2(A3)                         | push button rect for framing
        MOVE.L  #0x00100010,-(SP)               | corner radius 16x16 for round rect
        _FrameRoundRect                         | frame the button
        ADDA.W  #0xC,A3                         | advance to next button (12 bytes)
        SUBQ.W  #0x1,D3                         | decrement button count
        BNE.B   DRAW_BTN_LOOP                   | more buttons - draw next
        MOVE.L  (A5),A0                         | A0 = QD globals
        PEA.L     -0x6C(A0)                     | push arrow cursor data ptr
        _SetCursor                              | set cursor to arrow
        _ShowCursor                             | make cursor visible
        MOVE    #0x2000,SR                      | enable interrupts for mouse tracking
        ST      (CrsrCouple).w                  | couple cursor to mouse movement
        CLR.B   (VBLQueueHdr_Flags).w           | enable VBL tasks for cursor
WAIT_MOUSE_DOWN:
        BTst    #0x3,(VIA_Base).l               | test VIA port B bit 3: mouse button

        BNE.B   WAIT_MOUSE_DOWN                 | button up - keep polling
        MOVE.L  A2,A3                           | reset A3 to button def base
        MOVE    (A3)+,D3                        | D3 = button count
        ADDQ.W  #0x2,A3                         | skip text ID, point to first rect
HITTEST_BTN_LOOP:
        BSR.B   BTN_PT_IN_RECT                  | test if mouse is in this button rect
        BNE.B   HITTEST_BTN_LOOP_OK             | yes - begin tracking this button
        ADDA.W  #0xC,A3                         | advance to next button entry
        SUBQ.W  #0x1,D3                         | decrement button count
        BNE.B   HITTEST_BTN_LOOP                | more buttons - check next
        BRA.B   WAIT_MOUSE_DOWN                 | no hit - wait for another click
HITTEST_BTN_LOOP_OK:
        BSR.B   BTN_INVERT                      | invert hit button (initial highlight)
        MOVEQ    #0x1,D3                        | D3 = 1 (current highlight state = on)
TRACK_BTN_POLL:
        BSR.B   BTN_PT_IN_RECT                  | is mouse still in button rect?
        CMP.B   D0,D3                           | highlight state matches mouse pos?
        BEQ.B   TRACK_BTN_CHECK                 | yes - no change needed
        EORI    #0x1,D3                         | toggle highlight state
        BSR.B   BTN_INVERT                      | invert button (toggle highlight)
TRACK_BTN_CHECK:                                | poll mouse-button state
        BTst    #0x3,(VIA_Base).l               | mouse button still down?
        BEQ.B   TRACK_BTN_POLL                  | button still down: keep tracking
        TST.B   D3                              | was button highlighted at mouse-up?
        BEQ.B   WAIT_MOUSE_DOWN                 | no: click cancelled, wait again
        MOVE    8(A3),D0                        | D0 = button-handler resource ID
        BSR.W   LOOKUP_ALERT_ID                 | look up handler in alert table
        RTS                                     | return with Z from LOOKUP_ALERT_ID

| ----------------------------------------------------------
| BTN_PT_IN_RECT - test if mouse is inside button rect at A3
| Returns D0 nonzero if mouse point is inside the rect.
BTN_PT_IN_RECT:
        SUBQ.W  #0x2,SP                         | make room for Boolean result
        MOVE.L  (Mouse_v).w,-(SP)               | push current mouse position (v.h)
        MOVE.L  A3,-(SP)                        | push button rect ptr
        _PtInRect                               | test point-in-rect
        MOVE.B  (SP)+,D0                        | pop Boolean result into D0
        RTS                                     | return with hit test result
BTN_INVERT:
        MOVE.L  A3,-(SP)                        | push button rect ptr
        MOVE.L  #0x100010,-(SP)                 | corner radius 16x16
        _InvertRoundRect                        | toggle button highlight
        RTS                                     | return from inversion
