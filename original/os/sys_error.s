| System Error Handler -- _SysBeep, _SysError, the system error alert
|
| The 64K ROM's SysErr code (Mac Plus: os/sys_error.s, same structure):
| INSTALL_DSERR_TRAMP - give the alert's GrafPort fake visRgn/clipRgn
|                       handles (SysErrTrampoline: a wide-open region)
| SysBeep ($A9C8)     - beep through BootBeep
| SysError ($A9C9)    - save the registers, look the error up in the alert
|                       table (DSAlertTab: from the System file's DSAT
|                       resource, LOOKUP_ALERT_ID), draw the alert box,
|                       icon and text (DRAW_ALERT_TEXT, DRAW_ALERT_FRAME),
|                       draw and track the buttons (SHOW_ALERT_BTNS,
|                       TRACK_BTN_*, BTN_PT_IN_RECT, BTN_INVERT).
| The 64K ROM has no ROM debugger (the Mac Plus has MicroBug); a
| "Resume" button returns through the procedure the alert table names.
|
| References: Inside Macintosh Vol II, Ch 12 (The System Error Handler).

| ----------------------------------------------------------
| INSTALL_DSERR_TRAMP -- give the system error alert's GrafPort fake
| visRgn/clipRgn handles. Called by SysError just before _InitPort.
| Entry: A6 = the GrafPort (108 bytes; the two longs after it, A6+$6C
|        and A6+$70, serve as master pointers)
| visRgn := A6+$6C and clipRgn := A6+$70; both master pointers point
| to the static wide-open region at $091E (SysErrTrampoline).
| Apple source name: AllocFakeRgns (MacSEROM.lst: ALLOCFAKERGNS)
INSTALL_DSERR_TRAMP:
        LEA     0x18(A6),A1                     | A1 = &port.visRgn
        LEA     0x6C(A6),A0                     | A0 = A6+$6C: first fake master pointer
        MOVE.L  A0,(A1)+                        | visRgn := A6+$6C
        ADDQ.W  #0x4,A0                         | A0 = A6+$70: second fake master pointer
        MOVE.L  A0,(A1)+                        | clipRgn := A6+$70
        LEA     SysErrTrampoline(PC),A1         | A1 = static region @ $091E
        MOVE.L  A1,(A0)                         | clipRgn master pointer -> region
        SUBQ.W  #0x4,A0                         | A0 = A6+$6C
        MOVE.L  A1,(A0)                         | visRgn master pointer -> region
        RTS                                     | return to SysError

| ----------------------------------------------------------
| SysErrTrampoline ($091E) -- not code: a 10-byte rectangular region
| (rgnSize 10, rgnBBox -30000,-30000,30000,30000) that serves as the
| visRgn and clipRgn of the system error alert's port.
SysErrTrampoline:
        .short  0x000A                          | rgnSize = 10 (rectangular region)
        .short  0x8AD0                          | rgnBBox.top = -30000
        .short  0x8AD0                          | rgnBBox.left = -30000
        .short  0x7530, 0x7530                  | rgnBBox.bottom = rgnBBox.right = 30000
| ----------------------------------------------------------
| _SysBeep ($A9C8): sound the system beep
| Pascal: PROCEDURE SysBeep(duration: INTEGER);
| Entry: duration (word, in ticks) on the stack above the return address
| Saves D0-D7/A1-A6 and runs the boot-beep generator BootBeep with
| D3 = duration and A3 = 0 (RAM base); BootBeep returns via A6 to
| SYSBEEP_EPILOG, which restores the registers and pops the parameter.
| (No speaker-volume check or menu-bar flash, unlike the Plus ROM.)
SysBeep:
        .short  0x48E7, 0xFF7E                  | MOVEM.L D0-D7/A1-A6,-(SP)
        MOVE    0x3C(SP),D3                     | D3 = duration (past 56 bytes of regs + ret)
        SUBA.L  A3,A3                           | A3 = 0: RAM base for the sound buffer
        LEA.L     SYSBEEP_EPILOG(PC),A6         | A6 = epilogue (pop regs + RTS)
        BRA.W   BootBeep                        | play the tone; returns via JMP (A6)

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
        BSR.B   INSTALL_DSERR_TRAMP             | fake visRgn/clipRgn for the port at A6
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
