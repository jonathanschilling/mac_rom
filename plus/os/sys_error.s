| System Error -- DS Alert Rendering and Mouse-Button Tracking
|
| Called from the DS error handler (classic: in boot/sad_mac.s tail;
| Plus: in debugger/debugger.s) after the alert's shape and contents
| have been determined. This file renders the alert frame, draws the
| text, lays out buttons, and tracks mouse-button clicks to dismiss
| or accept the alert.
|
| Routines:
| DRAW_ALERT_TEXT - parse '/'-separated text and draw each line.
| DRAWTEXT_SCAN / DRAWTEXT_SEGMENT / DRAWTEXT_DONE - text rendering.
| CALL_DS_DRAWPROC - invoke user-supplied DS draw hook (Plus only).
| INIT_ALERT_RECT / SET_DEFAULT_RECT / REPOS_ALERT_PORT
| - frame setup (Plus only; classic inlines the setup).
| DRAW_ALERT_FRAME - draw the 3D frame around the alert (classic
| uses the same name; see Phase 10B.84).
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
|
| CALL_DS_DRAWPROC - call DSDrawProc if installed
|
| If DSDrawProc is a valid pointer (positive nonzero), calls it
| to draw custom DS content. Sets bit 7 to prevent re-entrancy.
CALL_DS_DRAWPROC:
        MOVE.L  (DSDrawProc).w,D0               | D0 = user draw proc pointer
        BLE.B   INIT_ALERT_RECT                 | nil or negative - use default rect
        MOVE.L  D0,-(SP)                        | push proc address for RTS dispatch
        BSET    #0x7,(DSDrawProc).w             | set re-entrancy guard bit
        RTS                                     | jump to DSDrawProc

| ----------------------------------------------------------
|
| INIT_ALERT_RECT - initialize DS alert rectangle if not already set
|
INIT_ALERT_RECT:
        LEA.L   (DSAlertRect).w,A0              | A0 = alert rect location
        BTST    #0x7,(DSAlertRect).w            | already initialized?
        BEQ.B   REPOS_ALERT_PORT                | yes - just reposition port
| ----------------------------------------------------------
|
| SET_DEFAULT_RECT - set default DS alert rect and draw frame
|
| Default rect: top=64, left=32, bottom=190, right=480
SET_DEFAULT_RECT:
        MOVE.L  #0x400020,(A0)+                 | top=64, left=32
        MOVE.L  #0xBE01E0,(A0)                  | bottom=190, right=480
        SUBQ.L  #0x4,A0                         | back to rect start
        BSR.B   DRAW_ALERT_FRAME                | erase and frame the alert box
        BSET    #0x7,(DSAlertRect).w            | mark rect as initialized
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| REPOS_ALERT_PORT - reposition port to existing alert rect
|
REPOS_ALERT_PORT:
        BSR.B   DRAW_ALERT_FRAME                | erase and frame the alert box
        MOVE.L  (DSAlertRect).w,-(SP)           | push rect topLeft as port origin
        _MovePortTo                             | move port origin to alert position
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| DRAW_ALERT_FRAME - draw DS alert box frame (double-bordered rectangle)
|
| Draws the standard system error alert box: erase, frame,
| then inset by 3 pixels and draw a thicker (2x2) inner frame.
DRAW_ALERT_FRAME:
        MOVE.L  A0,-(SP)                        | push rect for InsetRect (later)
        MOVE.L  A0,-(SP)                        | push rect for InsetRect (later)
        MOVE.L  A0,-(SP)                        | push rect for FrameRect (inner)
        MOVE.L  A0,-(SP)                        | push rect for FrameRect (outer)
        MOVE.L  A0,-(SP)                        | push rect for EraseRect
        _EraseRect                              | clear alert area to white
        _FrameRect                              | draw 1-pixel outer border
        MOVE.L  #0x20002,-(SP)                  | pen size 2x2 for inner border
        _PenSize                                | set pen size to 2x2
        MOVE.L  #0x30003,-(SP)                  | inset rect by 3 pixels each side
        _InsetRect                              | shrink rect for inner border
        _FrameRect                              | draw 2-pixel inner border
        MOVE.L  #0xFFFDFFFD,-(SP)               | inset rect by -3 (restore original)
        _InsetRect                              | restore original rect dimensions
        _PenNormal                              | reset pen to 1x1, black
DRAW_FRAME_RTS:
        RTS                                     | return from border drawing

| ----------------------------------------------------------
|
| SHOW_ALERT_BTNS - display DS alert buttons and wait for mouse click
|
| Looks up button definition in alert table, draws rounded-rect
| buttons with labels, then waits for mouse click on a button.
| Returns Z=0 and A0=button handler if clicked, Z=1 if no buttons.
SHOW_ALERT_BTNS:
        BSR     LOOKUP_ALERT_ID                 | look up button def ID in table
        BEQ.B   DRAW_FRAME_RTS                  | not found - return (Z=1)
        MOVE.L  A0,A2                           | A2 = button definition base
        MOVE    (A0)+,D3                        | D3 = number of buttons
        MOVE.L  A0,A3                           | A3 = first button entry
DRAW_BTN_LOOP:
        MOVE.L  PORTBITS(A3),-(SP)              | push button rect topLeft
        ADDI.L  #0xE0004,(SP)                   | offset Y+14, X+4 for text baseline
        _MoveTo                                 | position pen for button label
        MOVE    (A3),D0                         | D0 = button label text ID
        BSR     LOOKUP_ALERT_ID                 | look up text in alert table
        SUBQ.W  #0x1,A0                         | back up to include length byte
        MOVE.L  A0,-(SP)                        | push pascal string ptr
        _DrawString                             | draw button label text
        PEA.L   PORTBITS(A3)                    | push button rect for framing
        MOVE.L  #0x100010,-(SP)                 | corner radius 16x16 for round rect
        _FrameRoundRect                         | frame the button
        ADDA    #0xC,A3                         | advance to next button (12 bytes)
        SUBQ.W  #0x1,D3                         | decrement button count
        BNE.B   DRAW_BTN_LOOP                   | more buttons - draw next
        MOVE.L  (A5),A0                         | A0 = QD globals
        PEA.L   -0x6C(A0)                       | push arrow cursor data ptr
        _SetCursor                              | set cursor to arrow
        _ShowCursor                             | make cursor visible
        MOVE    #0x2000,SR                      | enable interrupts for mouse tracking
        ST.B    (CrsrCouple).w                  | couple cursor to mouse movement
        CLR.B   (VBLQueueHdr_Flags).w           | enable VBL tasks for cursor
WAIT_MOUSE_DOWN:
        BTst    #0x3,(VIA_Base).l               | test VIA port B bit 3: mouse button

        BNE.B   WAIT_MOUSE_DOWN                 | button up - keep polling
        MOVE.L  A2,A3                           | reset A3 to button def base
        MOVE    (A3)+,D3                        | D3 = button count
        ADDQ.W  #0x2,A3                         | skip text ID, point to first rect
HITTEST_BTN_LOOP:
        BSR.B   BTN_PT_IN_RECT                  | test if mouse is in this button rect
        BNE.B   TRACK_BTN_MOUSE                 | yes - begin tracking this button
        ADDA    #0xC,A3                         | advance to next button entry
        SUBQ.W  #0x1,D3                         | decrement button count
        BNE.B   HITTEST_BTN_LOOP                | more buttons - check next
        BRA.B   WAIT_MOUSE_DOWN                 | no hit - wait for another click

| ----------------------------------------------------------
|
| TRACK_BTN_MOUSE - track mouse while button is held down
|
| Highlights the button under the mouse (invert), and tracks
| mouse movement in/out of the button rect until mouse-up.
TRACK_BTN_MOUSE:
        BSR.B   BTN_INVERT                      | invert button (highlight)
        MOVEQ.L #0x1,D3                         | D3 = 1 = currently highlighted
TRACK_BTN_POLL:
        BSR.B   BTN_PT_IN_RECT                  | is mouse still in button rect?
        CMP.B   D0,D3                           | highlight state matches mouse pos?
        BEQ.B   TRACK_BTN_CHECK                 | yes - no change needed
        EORI    #0x1,D3                         | toggle highlight state
        BSR.B   BTN_INVERT                      | invert button (toggle highlight)
TRACK_BTN_CHECK:
        BTst    #0x3,(VIA_Base).l               | mouse button still down?

        BEQ.B   TRACK_BTN_POLL                  | yes - keep tracking
        TST.B   D3                              | was button highlighted at mouse-up?
        BEQ.B   WAIT_MOUSE_DOWN                 | no - click cancelled, wait again
        MOVE    PORTBOUNDS(A3),D0               | D0 = button handler ID
        BSR     LOOKUP_ALERT_ID                 | look up handler in alert table
        RTS                                     | return with Z flag from LOOKUP_ALERT_ID

| ----------------------------------------------------------
|
| BTN_PT_IN_RECT - test if mouse is inside button rect at A3
|
| Returns D0 nonzero if mouse point is inside the rect.
BTN_PT_IN_RECT:
        SUBQ.W  #0x2,SP                         | make room for Boolean result
        MOVE.L  (Mouse_v).w,-(SP)               | push current mouse position (v.h)
        MOVE.L  A3,-(SP)                        | push button rect ptr
        _PtInRect                               | test point-in-rect
        MOVE.B  (SP)+,D0                        | pop Boolean result into D0
        RTS                                     | return with hit test result

| ----------------------------------------------------------
|
| BTN_INVERT - invert (highlight/unhighlight) button at A3
|
BTN_INVERT:
        MOVE.L  A3,-(SP)                        | push button rect ptr
        MOVE.L  #0x100010,-(SP)                 | corner radius 16x16
        _InvertRoundRect                        | toggle button highlight
        RTS                                     | return from inversion

