| System Error Handler -- _SysError, the system error alert, _SysBeep
|
| Apple source: SysErr.a (System 7.1: StartErr.a and StartAlert.a;
| MacSEROM.lst module SYSTEMERROR). In ROM order:
|   SysError ($A9C9), SysErr2 - save the registers, hand the error to an
|                     installed debugger or to the built-in alert
|   AllocFakeRgns   - give the alert's GrafPort fake visRgn/clipRgn (the
|                     alert must not depend on the Memory Manager)
|   SysBeep ($A9C8) - flash the menu bar (volume 0) or sound BootBeep's
|                     square wave
|   DSErrorHandler  - the system error alert: look up the error in the
|                     alert table (DSAlertTab, from the System file's DSAT
|                     resource), draw the box, icon and text, draw the
|                     buttons and track them (DRAW_ALERT_TEXT, CALL_DS_DRAWPROC,
|                     INIT_ALERT_RECT ... DRAW_ALERT_FRAME, SHOW_ALERT_BTNS,
|                     TRACK_BTN_*, BTN_PT_IN_RECT, BTN_INVERT)
| The exception vectors and _Debugger are in debugger/debugger.s, MicroBug
| (entered when the alert's "Resume"/debugger path asks for it) in
| debugger/microbug.s.
|
| References: Inside Macintosh Vol II, Ch 12 (The System Error Handler);
| Technical Note TN1136 (MicroBug).

| ----------------------------------------------------------
|
| SysError - system error/debugger entry point
|
| Entered from _SysError trap, exception vectors, or _Debugger.
| D0 contains the error code (dsErrCode) on entry.
SysError:
        MOVEM.L D0-D7/A0-A7,(0x3FFC80).l        | save all regs to SEVarBase

        MOVE    SR,(0x3FFCC4).l                 | save SR to MacsBugSR
        MOVE.L  (SP)+,(0x3FFCC0).l              | save return addr to MacsBugPC
        TST.B   (CPUFlag).w                     | 68000 or 68020+?
        BEQ.B   SysErr2                         | 68000: no format word on stack
        CLR     -(SP)                           | 68020+: push dummy format word
SysErr2:
        TST.B   (MacJmp).w                      | bit 7: debugger already active?
        BMI.B   DBG_SKIP_SP_SAVE                | skip SP save if re-entering
        MOVE.L  A7,(0x3FFCBC).l                 | save SP at exception time
DBG_SKIP_SP_SAVE:
        BSet    #0x7,(MacJmp).w                 | mark debugger as active
        MOVE    D0,(DSErrCode).w                | store error code for display
        BSR     DebugProlog                     | check for installed debugger
        BPL.B   ICDISP_NO_DEBUGGER              | N=0: no debugger or DS handler
        BNE.B   DBG_CALL_HANDLER                | N=1,Z=0: debugger found in A1
ICDISP_NO_DEBUGGER:
        CMPI    #0xD,D0                         | error 13 = "MicroBug entry"?
        BNE.B   DBG_USE_DS_HANDLER              | no - use DS error handler
        MOVEQ.L #0x0,D0                         | clear error code for MicroBug
        BRA.B   DBG_CALL_HANDLER                | enter debugger handler in A1

| ----------------------------------------------------------
|
| DBG_USE_DS_HANDLER - default: use built-in DS error handler
|
DBG_USE_DS_HANDLER:
        LEA.L   DSErrorHandler(PC),A1           | point A1 to ROM DS handler
DBG_CALL_HANDLER:
        JSR     (A1)                            | call debugger or DS handler
        TST     D0                              | handler returns 0 = resume
        BNE.B   DBG_USE_DS_HANDLER              | nonzero = re-enter DS handler
        BCLR    #0x7,(MacJmp).w                 | clear debugger-active flag
        MOVEM.L (0x3FFC80).l,D0-D7/A0-A7        | restore all regs from save area

        MOVE.L  (0x3FFCC0).l,-(SP)              | push saved PC for RTE
        MOVE    (0x3FFCC4).l,-(SP)              | push saved SR for RTE
        RTE                                     | return from exception
| ----------------------------------------------------------
|
| AllocFakeRgns - set up fake visRgn/clipRgn for DS GrafPort
|
| The DS error handler creates a minimal GrafPort on the stack.
| A6 points to the port; offsets +0x18/+0x1C are visRgn/clipRgn
| handles. This allocates fake region data in the port's local
| storage area at offset +0x6C, pointing both regions at a
| rectangular region covering the entire screen stored at Scratch20.
AllocFakeRgns:
        LEA.L   0x18(A6),A1                     | A1 = &port.visRgn handle slot
        LEA.L   0x6C(A6),A0                     | A0 = local storage for fake handles
        MOVE.L  A0,(A1)+                        | visRgn handle -> local storage[0]
        ADDQ.W  #0x4,A0                         | advance to next handle slot
        MOVE.L  A0,(A1)+                        | clipRgn handle -> local storage[1]
        LEA.L   (Scratch20).w,A1                | A1 = Scratch20 (region data buffer)
        MOVE.L  A1,(A0)                         | clipRgn handle -> Scratch20
        SUBQ.W  #0x4,A0                         | back to visRgn handle
        MOVE.L  A1,(A0)                         | visRgn handle -> Scratch20
| ----------------------------------------------------------
|
| INSTALL_INF_RGN - install infinite bounding region into Scratch20
|
| Copies 10-byte region struct (size=10, bbox=0x8001..0x7FFF)
| to Scratch20. Both visRgn and clipRgn point here.
INSTALL_INF_RGN:
        LEA.L   (Scratch20).w,A1                | destination: Scratch20 low-mem
        LEA.L   INF_RGN_TEMPLATE(PC),A0         | source: infinite region template
        MOVEQ.L #0xA,D0                         | 10 bytes = region header size
        _BlockMove                              | copy region data to Scratch20
        RTS                                     | return from region allocation

| ----------------------------------------------------------
|
| INF_RGN_TEMPLATE - infinite region template (10 bytes)
|
| Region: size=10, rgnBBox=(-32767,-32767,32767,32767)
INF_RGN_TEMPLATE:
  .byte 0x00,0x0A,0x80,0x01,0x80,0x01
  .byte 0x7F,0xFF,0x7F,0xFF

| ----------------------------------------------------------
|
| SysBeep - _SysBeep trap handler
|
| Plays the system alert sound if available, or flashes the
| menu bar if sound is busy or volume is zero.
SysBeep:
        MOVEM.L D0-D7/A1-A6,-(SP)               | save working regs
        TST.B   (SoundActive).w                 | sound driver currently in use?
        BNE.B   SYSBEEP_FLASH                   | yes - fall through to visual flash
        TST.B   (SdVolume).w                    | speaker volume = 0?
        BNE.B   SYSBEEP_AUDIBLE                 | nonzero - play audible beep
SYSBEEP_FLASH:
        TST.B   (WWExist).w                     | Window Manager initialized?
        BNE.B   SYSBEEP_EPILOG                  | no - skip flash, just return
        CLR.L   -(SP)                           | push 0 (flash menu bar)
        _FlashMenuBar                           | invert menu bar
        SUBA.L  A0,A0                           | A0 = 0
        ADDQ.W  #0x8,A0                         | A0 = 8 ticks delay
        _Delay                                  | wait ~133ms
        _FlashMenuBar                           | restore menu bar
        BRA.B   SYSBEEP_EPILOG                  | done

| ----------------------------------------------------------
|
| SYSBEEP_AUDIBLE - audible beep via BootBeep square wave
|
SYSBEEP_AUDIBLE:
        MOVE    0x3C(SP),D3                     | D3 = saved SR from stack frame
        LEA.L   SYSBEEP_EPILOG(PC),A6           | A6 = return address after beep
        BRA     BootBeep                        | play square wave beep

| ----------------------------------------------------------
|
| SYSBEEP_EPILOG - SysBeep epilogue, pops duration param and returns
|
SYSBEEP_EPILOG:
        MOVEM.L (SP)+,D0-D7/A1-A6               | restore working regs
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x2,SP                         | discard duration parameter (word)
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| COPY_ALERT_RECT - copy DSAlertRect and offset to GrafPort origin
|
| Copies the 8-byte alert rectangle to Scratch20_2, clears
| the high bit (used as "rect initialized" flag), then offsets
| the rect by the GrafPort's portBits.bounds.topLeft.
COPY_ALERT_RECT:
        LEA.L   (DSAlertRect).w,A0              | source: DS alert rectangle
        LEA.L   (Scratch20_2).w,A1              | dest: scratch area
        MOVEQ.L #0x8,D0                         | 8 bytes = Rect struct
        _BlockMove                              | copy alert rect to scratch
        MOVE.L  A1,-(SP)                        | push rect ptr for OffsetRect
        BCLR    #0x7,(A1)                       | clear "initialized" flag bit
        MOVE.L  (A5),A0                         | A5 = QD globals; dereference
        MOVE.L  (A0),A0                         | dereference handle to GrafPort
        MOVE.L  0x8(A0),-(SP)                   | push portBits.bounds.topLeft
        _OffsetRect                             | offset rect to port coords
        RTS                                     | return from COPY_ALERT_RECT

| ----------------------------------------------------------
|
| DSErrorHandler - system error alert display
|
| Creates a temporary GrafPort on the stack, initializes
| QuickDraw, and displays the system error dialog using the
| alert table pointed to by DSAlertTab. If no alert table
| is installed, falls through to CritErr for a minimal display.
DSErrorHandler:
        MOVE    #0x2000,SR                      | enter supervisor, enable interrupts
        MOVE    (CurMap).w,-(SP)                | save current resource map
        MOVE    (SysMap).w,(CurMap).w           | switch to system resource map
        LEA.L   -0x4(SP),A5                     | A5 = QD globals ptr (above stack)
        SUBA    #0x15A,SP                       | allocate stack frame for GrafPort
        MOVE.L  A7,A6                           | A6 = base of temp GrafPort
        PEA.L   -0x4(A5)                        | push ptr for InitGraf thePort
        MOVE.B  (QDExist).w,D3                  | save QDExist state
        _InitGraf                               | init QuickDraw globals
        MOVE.B  D3,(QDExist).w                  | restore QDExist (may not be ready)
        BSR     AllocFakeRgns                   | set up fake visRgn/clipRgn
        MOVE.L  A6,-(SP)                        | push GrafPort ptr
        _InitPort                               | init the temporary port
        MOVE    (DSErrCode).w,-(SP)             | push error code for display
        MOVE.L  (DSAlertTab).w,D7               | D7 = ptr to system error alert table
        BNE.B   DSERR_DISPATCH                  | table exists - use it
        MOVE    (SP)+,D1                        | pop error code into D1
        MOVE    #0xF,A4                         | A4 = 15 (button flags for CritErr)
        SUBA.L  A3,A3                           | A3 = nil (no alert text)
        BRA     CritErr                         | show minimal "sorry" error box

| ----------------------------------------------------------
|
| DSERR_DISPATCH - dispatch on error code using alert table
|
DSERR_DISPATCH:
        MOVE    (SP),D0                         | peek at error code
        BMI.B   DSERR_SETUP_RECT                | negative = don't draw custom proc
        CMPI    #0xD,D0                         | error 13 = MicroBug entry?
        BEQ     MICROBUG_ENTRY                  | yes - enter MicroBug command loop
        BSR     CALL_DS_DRAWPROC                | call DSDrawProc if installed
DSERR_SETUP_RECT:
        BSR.B   COPY_ALERT_RECT                 | copy and offset alert rect
        MOVE    (SP)+,D0                        | pop error code
        BSR.B   LOOKUP_ALERT_ID                 | look up error code in alert table
        BNE.B   DSERR_DRAW_ALERT                | found - A0 points to alert def
        MOVE.L  D7,A0                           | not found - use default alert
        ADDQ.L  #0x6,A0                         | skip table header (count + first ID)
DSERR_DRAW_ALERT:
        MOVE.L  A0,A3                           | A3 = ptr to alert definition fields
        BSR.B   DRAW_ALERT_TEXT                 | draw first text string
        BSR.B   DRAW_ALERT_TEXT                 | draw second text string
        MOVE    (A3)+,D0                        | icon resource ID
        BEQ.B   DSERR_SKIP_ICON                 | 0 = no icon
        BSR.B   LOOKUP_ALERT_ID                 | look up icon ID in table
        BEQ.B   DSERR_SKIP_ICON                 | not found - skip icon
        PEA.L   0x8(A0)                         | push icon rect ptr (after icon data)
        MOVE.L  A0,-(SP)                        | push icon data ptr
        PEA.L   0x4(SP)                         | push dest rect on stack
        _PlotIcon                               | draw the alert icon
        ADDQ.W  #0x4,SP                         | pop extra rect ptr
DSERR_SKIP_ICON:
        MOVE    (A3)+,D0                        | procedure resource ID
        BEQ.B   DSERR_SKIP_PROC                 | 0 = no custom procedure
        BSR.B   LOOKUP_ALERT_ID                 | look up procedure in table
        BEQ.B   DSERR_SKIP_PROC                 | not found - skip
        JSR     (A0)                            | call custom alert procedure
DSERR_SKIP_PROC:
        MOVE    (A3)+,D0                        | button definition ID
        BEQ.B   DSERR_RESUME                    | 0 = no buttons, auto-resume
        TST.L   (ResumeProc).w                  | resume procedure installed?
        BEQ.B   DSERR_SHOW_BTNS                 | no - use button count as-is
        ADDQ.W  #0x1,D0                         | yes - add Resume button option
DSERR_SHOW_BTNS:
        BSR     SHOW_ALERT_BTNS                 | display buttons and wait for click
        BNE.B   DSERR_BTN_CLICKED               | button clicked - handle choice
DSERR_RESUME:
        BSR     INSTALL_INF_RGN                 | restore region data to Scratch20
        ADDA    #0x15A,SP                       | deallocate temp GrafPort frame
        MOVE    (SP)+,(CurMap).w                | restore resource map
        MOVEQ.L #0x0,D0                         | return 0 = resume execution
        RTS                                     | return to system error dispatcher

| ----------------------------------------------------------
|
| DSERR_BTN_CLICKED - button was clicked, clean up and return via button handler
|
DSERR_BTN_CLICKED:
        MOVE.L  A0,-(SP)                        | push button handler address
        BSR     INSTALL_INF_RGN                 | restore region data to Scratch20
        RTS                                     | jump to button handler via pushed addr

| ----------------------------------------------------------
|
| LOOKUP_ALERT_ID - look up ID in DS alert table
|
| Searches the alert table (pointed to by D7) for entry
| matching D0. Returns Z=0 and A0=entry data if found,
| Z=1 and A0=0 if not found.
| Called by: DSERR_SETUP_RECT, DSERR_DRAW_ALERT, DSERR_SKIP_ICON, DRAW_ALERT_TEXT, SHOW_ALERT_BTNS (and 2 more)
LOOKUP_ALERT_ID:
        MOVE.L  D7,A0                           | A0 = alert table base
        MOVE    (A0)+,D1                        | D1 = entry count
        BRA.B   LOOKUP_NEXT                     | enter loop

| ----------------------------------------------------------
|
| LOOKUP_LOOP - alert table search loop
|
LOOKUP_LOOP:
        CMP     (A0)+,D0                        | compare ID with table entry
        BEQ.B   LOOKUP_FOUND                    | match - return this entry
        ADDA    (A0)+,A0                        | skip entry data (offset to next)
LOOKUP_NEXT:
        DBF     D1,LOOKUP_LOOP                  | loop through all entries
        MOVEQ.L #0x0,D0                         | not found: D0=0, Z=1
        SUBA.L  A0,A0                           | A0 = nil
        RTS                                     | return with Z flag set (not found)

| ----------------------------------------------------------
|
| LOOKUP_FOUND - alert table entry found
|
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
        RTS                                     | return from SET_DEFAULT_RECT

| ----------------------------------------------------------
|
| REPOS_ALERT_PORT - reposition port to existing alert rect
|
REPOS_ALERT_PORT:
        BSR.B   DRAW_ALERT_FRAME                | erase and frame the alert box
        MOVE.L  (DSAlertRect).w,-(SP)           | push rect topLeft as port origin
        _MovePortTo                             | move port origin to alert position
        RTS                                     | return from REPOS_ALERT_PORT

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
        MOVE.L  0x2(A3),-(SP)                   | push button rect topLeft (entry +2)
        ADDI.L  #0xE0004,(SP)                   | offset Y+14, X+4 for text baseline
        _MoveTo                                 | position pen for button label
        MOVE    (A3),D0                         | D0 = button label text ID
        BSR     LOOKUP_ALERT_ID                 | look up text in alert table
        SUBQ.W  #0x1,A0                         | back up to include length byte
        MOVE.L  A0,-(SP)                        | push pascal string ptr
        _DrawString                             | draw button label text
        PEA.L   0x2(A3)                         | push button rect (entry +2) for framing
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
        MOVE    0x8(A3),D0                      | D0 = button handler ID (word after the rect)
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

