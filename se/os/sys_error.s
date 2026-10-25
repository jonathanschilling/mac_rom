| System Error Handler -- _SysError, the system error alert, _SysBeep
|
| Apple sources: StartErr.a and StartAlert.a (MacSEROM.lst module
| SYSTEMERROR). In ROM order (the SE has SysBeep with the startup test
| code in boot/memtest.s):
|   SysError ($A9C9), SysErr2 - save the registers, hand the error to an
|                     installed debugger or to the built-in alert
|   AllocFakeRgns   - give the alert's GrafPort fake visRgn/clipRgn (the
|                     alert must not depend on the Memory Manager)
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
| SYSTEMERROR - _SysError trap handler entry
| Saves registers, captures SR/PC, then dispatches to DS handler.
| D0 = system error code on entry.
SYSTEMERROR:
    MOVEM.L     D0-D7/A0-A7,(0x3FFC80).L        | save all registers to SERegs
    MOVE.W      SR,(0x3FFCC4).L                 | save current SR to MacsBugSR
    MOVE.L      (A7)+,(0x3FFCC0).L              | save return PC to MacsBugPC
    TST.B       (CPUFlag).W                     | 68000 or 68020+?
    BEQ.B       SYSERR2                         | 68000: no format word
    CLR.W       -(A7)                           | 68020+: push dummy format word
| ----------------------------------------------------------
| SYSERR2 - system error dispatch: save SP, check debugger, call handler
| D0 = error code. Tries external debugger first, falls back to
| built-in DSErrorHandler. If handler returns 0, resume from error.
SYSERR2:
    TST.B       (MacJmp).W                      | debugger already active (bit 7)?
    BMI.B       DBG_SKIP_SP_SAVE                | yes: don't overwrite saved SP
    MOVE.L      A7,(0x3FFCBC).L                 | save exception SP to SERegs+$3C
DBG_SKIP_SP_SAVE:
    BSET        #0x7,(MacJmp)                   | set debugger-active flag
    MOVE.W      D0,(DSErrCode).W                | store error code for display
    BSR.W       DEBUGPROLOG                     | check MacJmp: A1=debugger, CC=flags
    BPL.B       SYSERR_TRY_DEBUGGER             | debugger installed (not active): try it
    BNE.B       SYSERR_DISPATCH                 | debugger active: dispatch to it
| No debugger or debugger not ready
SYSERR_TRY_DEBUGGER:
    CMPI.W      #0xD,D0                         | error 13 (dsNoPk: unimplemented)?
    BNE.B       SYSERR_USE_DS                   | no: use DS handler
    MOVEQ.L     #0x0,D0                         | yes: clear error, dispatch to debugger
    BRA.B       SYSERR_DISPATCH                 | let debugger handle it
SYSERR_USE_DS:
    LEA.L       DSERRORHANDLER(PC),A1           | A1 = built-in DS error handler
SYSERR_DISPATCH:
    MOVE.L      A1,D1                           | is handler nil?
    BEQ.B       SYSERR_USE_DS                   | nil: fall back to DS handler
    JSR         (A1)                            | call error handler (debugger or DS)
    TST.W       D0                              | handler wants to resume (D0=0)?
    BNE.B       SYSERR_USE_DS                   | no: try DS handler instead
| Handler returned 0: resume from error
    BCLR        #0x7,(MacJmp)                   | clear debugger-active flag
    MOVEM.L     (0x3FFC80).L,D0-D7/A0-A7        | restore all registers from SERegs
    MOVE.L      (0x3FFCC0).L,-(A7)              | push saved PC for RTE
    MOVE.W      (0x3FFCC4).L,-(A7)              | push saved SR for RTE
    .byte 0x4E,0x73                             | RTE: return from exception
| ALLOCFAKERGNS - called from 2 places

| ----------------------------------------------------------
| ALLOCFAKERGNS - set up fake visRgn/clipRgn for DS alert GrafPort
| Points the GrafPort's visRgn and clipRgn handles to stack-allocated
| handles that both dereference to Scratch20 (infinite region).
| A6 = GrafPort base.
ALLOCFAKERGNS:
    LEA.L       0x18(A6),A1                     | A1 = visRgn handle field
    LEA.L       0x6C(A6),A0                     | A0 = stack space for fake handles
    MOVE.L      A0,(A1)+                        | visRgn handle = fake handle 1
    ADDQ.W      #0x4,A0                         | A0 = next fake handle slot
    MOVE.L      A0,(A1)+                        | clipRgn handle = fake handle 2
    LEA.L       (Scratch20).W,A1                | A1 = infinite region data
    MOVE.L      A1,(A0)                         | fake handle 2 -> Scratch20
    SUBQ.W      #0x4,A0                         | back to fake handle 1
    MOVE.L      A1,(A0)                         | fake handle 1 -> Scratch20
| ----------------------------------------------------------
|
| INSTALL_INF_RGN - install infinite bounding region into Scratch20
|
| Copies 10-byte region struct (size=10, bbox=0x8001..0x7FFF)
| to Scratch20. Both visRgn and clipRgn point here.
INSTALL_INF_RGN:
    LEA.L       (Scratch20).W,A1                | destination: Scratch20 low-mem
    LEA.L       DT_INF_RGN(PC),A0               | A0 = infinite region template
    MOVEQ.L     #0xA,D0                         | D0 = 10 bytes (Region struct)
    _BlockMove                                  | copy infinite region to Scratch20
    RTS                                         | return from INSTALL_INF_RGN
| DT_INF_RGN - infinite bounding region (10 bytes)
| rgnSize=10, rgnBBox = (-32767,-32767,32767,32767)
DT_INF_RGN:
    .short      0x000A                          | rgnSize = 10 (rectangular)
    .long       0x80018001                      | top=-32767, left=-32767
    .long       0x7FFF7FFF                      | bottom=32767, right=32767
| ----------------------------------------------------------
|
| COPY_ALERT_RECT - copy DSAlertRect and offset to GrafPort origin
|
| Copies the 8-byte alert rectangle to Scratch20_2, clears
| the high bit (used as "rect initialized" flag), then offsets
| the rect by the GrafPort's portBits.bounds.topLeft.
COPY_ALERT_RECT:
    LEA.L       (DSAlertRect).W,A0              | source: DS alert rectangle
    LEA.L       (Scratch20_2).W,A1              | dest: scratch area
    MOVEQ.L     #0x8,D0                         | 8 bytes = Rect struct
    _BlockMove                                  | copy alert rect to scratch
    MOVE.L      A1,-(A7)                        | push rect ptr for OffsetRect
    BCLR        #0x7,(A1)                       | clear "rect initialized" flag
    MOVEA.L     (A5),A0                         | A0 = QD globals handle
    MOVEA.L     (A0),A0                         | A0 = deref QD globals
    MOVE.L      0x8(A0),-(A7)                   | push portBits.bounds.topLeft
    _OffsetRect                                 | offset alert rect by port origin
    RTS                                         | return from COPY_ALERT_RECT
| ----------------------------------------------------------
| DSERRORHANDLER - built-in DS alert (system error dialog)
| Draws the system error alert box with error text, Restart
| and Resume buttons. Uses QuickDraw for rendering.
| D0 = error code on entry.
DSERRORHANDLER:
    MOVE.W      #0x2000,SR                      | drop to IPL=0 (enable interrupts)
    MOVE.W      (CurMap).W,-(A7)                | save current resource map
    MOVE.W      (SysMap).W,(CurMap).W           | switch to system resource map
    LEA.L       -0x4(A7),A5                     | A5 = QD globals ptr on stack
    SUBA.W      #0x15A,A7                       | allocate DS GrafPort + workspace
    MOVEA.L     A7,A6                           | A6 = GrafPort base
    PEA.L       -0x4(A5)                        | push @thePort
    MOVE.B      (QDExist).W,D3                  | save QDExist (may already be init'd)
    _InitGraf                                   | initialize QuickDraw
    MOVE.B      D3,(QDExist).W                  | restore QDExist
    BSR.B       ALLOCFAKERGNS                   | set up fake visRgn/clipRgn
    MOVE.L      A6,-(A7)                        | push GrafPort
    _InitPort                                   | initialize DS GrafPort
    MOVE.W      (DSErrCode).W,-(A7)             | push error code for display
    MOVE.L      (DSAlertTab).W,D7               | D7 = DS alert table pointer
    BNE.B       DSERR_HAS_TABLE                 | table exists: use it
| No DSAT resource loaded: show raw error via boot-time sad Mac
    MOVEQ.L     #0x0,D6                         | D6 = 0
    MOVE.W      (A7)+,D6                        | D6 = error code (low word)
    CLR.W       D7                              | D7 = 0 (high word)
    MOVE.W      #0xF,D7                         | D7 = $F (sad Mac error category)
    JMP         (0x401092).L                    | jump to CRITERR (sad Mac display)
DSERR_HAS_TABLE:
    MOVE.W      (A7),D0                         | D0 = error code (peek, keep on stack)
    BMI.B       DSERR_SETUP_RECT                | negative error: skip draw proc
    CMPI.W      #0xD,D0                         | error 13 (dsNoPk)?
    BEQ.W       MICROBUG_ENTRY                  | yes: enter MicroBug debugger
    BSR.W       CALL_DS_DRAWPROC                | call custom draw procedure
DSERR_SETUP_RECT:
    BSR.B       COPY_ALERT_RECT                 | copy and offset alert rect
    MOVE.W      (A7)+,D0                        | D0 = error code (pop)
    BSR.B       LOOKUP_ALERT_ID                 | look up error in alert table
    BNE.B       DSERR_DRAW_ALERT                | found: draw it
    MOVEA.L     D7,A0                           | not found: use default alert
    ADDQ.L      #0x6,A0                         | skip table header (6 bytes)
DSERR_DRAW_ALERT:
    MOVEA.L     A0,A3                           | A3 = alert entry data
    BSR.B       DRAW_ALERT_TEXT                 | draw alert title text
    BSR.B       DRAW_ALERT_TEXT                 | draw alert message text
    MOVE.W      (A3)+,D0                        | D0 = icon ID
    BEQ.B       DSERR_SKIP_ICON                 | no icon: skip
    BSR.B       LOOKUP_ALERT_ID                 | look up icon data
    BEQ.B       DSERR_SKIP_ICON                 | not found: skip
    PEA.L       0x8(A0)                         | push icon data (past rect)
    MOVE.L      A0,-(A7)                        | push icon rect
    PEA.L       0x4(A7)                         | push dst rect on stack
    _PlotIcon                                   | draw icon in alert
    ADDQ.W      #0x4,A7                         | clean stack
DSERR_SKIP_ICON:
    MOVE.W      (A3)+,D0                        | D0 = custom proc ID
    BEQ.B       DSERR_SKIP_PROC                 | no proc: skip
    BSR.B       LOOKUP_ALERT_ID                 | look up proc address
    BEQ.B       DSERR_SKIP_PROC                 | not found: skip
    JSR         (A0)                            | call custom alert procedure
DSERR_SKIP_PROC:
    MOVE.W      (A3)+,D0                        | D0 = button count
    BEQ.B       DSERR_RESUME                    | no buttons: resume directly
    TST.L       (ResumeProc).W                  | is ResumeProc installed?
    BEQ.B       DSERR_SHOW_BTNS                 | no: show D0 buttons
    ADDQ.W      #0x1,D0                         | yes: add Resume button
DSERR_SHOW_BTNS:
    BSR.W       SHOW_ALERT_BTNS                 | show buttons, wait for click
    BNE.B       DSERR_RESTART                   | button click: restart
DSERR_RESUME:
    BSR.W       INSTALL_INF_RGN                 | restore infinite region
    ADDA.W      #0x15A,A7                       | free DS GrafPort workspace
    MOVE.W      (A7)+,(CurMap).W                | restore saved resource map
    MOVEQ.L     #0x0,D0                         | D0 = 0 (resume from error)
    RTS                                         | return from DSErrorHandler
DSERR_RESTART:
    MOVE.L      A0,-(A7)                        | save restart proc address
    BSR.W       INSTALL_INF_RGN                 | restore infinite region
    RTS                                         | return (jump to restart proc)
| ----------------------------------------------------------
|
| LOOKUP_ALERT_ID - look up ID in DS alert table
|
| Searches the alert table (pointed to by D7) for entry
| matching D0. Returns Z=0 and A0=entry data if found,
| Z=1 and A0=0 if not found.
| Called by: DSERR_SETUP_RECT, DSERR_DRAW_ALERT, DSERR_SKIP_ICON, DRAW_ALERT_TEXT, SHOW_ALERT_BTNS (and 2 more)
| ----------------------------------------------------------
| LOOKUP_ALERT_ID - search DS alert table for entry matching D0
| D7 = alert table base. Table format: count word, then entries
| of (ID word, offset word). Returns Z=0 + A0=data if found.
LOOKUP_ALERT_ID:
    MOVEA.L     D7,A0                           | A0 = alert table base
    MOVE.W      (A0)+,D1                        | D1 = entry count
    BRA.B       LOOKUP_NEXT                     | enter search loop
LOOKUP_LOOP:
    CMP.W       (A0)+,D0                        | does this entry match D0?
    BEQ.B       LOOKUP_FOUND                    | yes: found it
    ADDA.W      (A0)+,A0                        | no: skip data, advance to next
LOOKUP_NEXT:
    DBF.W       D1,LOOKUP_LOOP                  | loop for all entries
    MOVEQ.L     #0x0,D0                         | not found: D0 = 0 (Z=1)
    SUBA.L      A0,A0                           | A0 = nil
    RTS                                         | return Z=1 (not found)
| ----------------------------------------------------------
|
| LOOKUP_FOUND - alert table entry found
|
LOOKUP_FOUND:
    MOVEQ.L     #-0x1,D0                        | D0 = -1 (NZ = found)
    ADDQ.W      #0x2,A0                         | A0 = skip offset word -> entry data
    RTS                                         | return Z=0 (found)
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
    MOVE.W      (A3)+,D0                        | D0 = text entry ID from alert data
    BEQ.B       DRAWTEXT_DONE                   | no text ID: skip
    BSR.B       LOOKUP_ALERT_ID                 | look up text in alert table
    BEQ.B       DRAWTEXT_DONE                   | not found: skip
    MOVE.L      (A0)+,D3                        | D3 = text position (v.h packed)
    MOVEA.L     A0,A2                           | A2 = start of text string
| Scan text for '/' (line separator) or NUL (end of string)
DRAWTEXT_SCAN:
    MOVE.B      (A0)+,D0                        | read next character
    BEQ.B       DRAWTEXT_SEGMENT                | NUL: end of string -> draw segment
    CMPI.B      #0x2F,D0                        | '/' line separator?
    BNE.B       DRAWTEXT_SCAN                   | no: keep scanning
| Draw one line segment from A2 to A0-1
DRAWTEXT_SEGMENT:
    MOVE.B      D0,-(A7)                        | save delimiter (NUL or '/')
    MOVE.L      A2,-(A7)                        | push text pointer for _DrawText
    CLR.W       -(A7)                           | push firstByte = 0
    MOVE.L      A0,D0                           | D0 = current position
    SUB.L       A2,D0                           | D0 = segment length + 1
    SUBQ.W      #0x1,D0                         | D0 = segment length
    MOVEA.L     A0,A2                           | A2 = start of next segment
    MOVE.W      D0,-(A7)                        | push byteCount
    MOVE.L      D3,-(A7)                        | push position (v, h)
    _MoveTo                                     | move pen to text position
    _DrawText                                   | draw text segment
    ADDI.L      #0xE0000,D3                     | advance Y by 14 pixels
    MOVEA.L     A2,A0                           | A0 = continue scanning from here
    MOVE.B      (A7)+,D0                        | D0 = saved delimiter
    BNE.B       DRAWTEXT_SCAN                   | not NUL: more lines to draw
DRAWTEXT_DONE:
    RTS                                         | return from DRAW_ALERT_TEXT
| ----------------------------------------------------------
|
| CALL_DS_DRAWPROC - call DSDrawProc if installed
|
| If DSDrawProc is a valid pointer (positive nonzero), calls it
| to draw custom DS content. Sets bit 7 to prevent re-entrancy.
CALL_DS_DRAWPROC:
    MOVE.L      (DSDrawProc).W,D0               | D0 = user draw proc pointer
    BLE.B       INIT_ALERT_RECT                 | nil or negative - use default rect
    MOVE.L      D0,-(A7)                        | push draw proc address (for RTS jump)
    BSET        #0x7,(DSDrawProc)               | set re-entrancy guard bit
    RTS                                         | "return" to draw proc (tail call)
| ----------------------------------------------------------
|
| INIT_ALERT_RECT - initialize DS alert rectangle if not already set
|
INIT_ALERT_RECT:
    LEA.L       (DSAlertRect).W,A0              | A0 = DS alert rectangle
    BTST        #0x7,(DSAlertRect)              | already initialized (bit 7)?
    BEQ.B       REPOS_ALERT_PORT                | yes: reposition to existing rect
| ----------------------------------------------------------
|
| SET_DEFAULT_RECT - set default DS alert rect and draw frame
|
| Default rect: top=64, left=32, bottom=190, right=480
SET_DEFAULT_RECT:
    MOVE.L      #0x400020,(A0)+                 | top=64, left=32
    MOVE.L      #0xBE01E0,(A0)                  | bottom=190, right=480
    SUBQ.L      #0x4,A0                         | back to rect start
    BSR.B       DRAW_ALERT_FRAME                | erase and frame the alert box
    BSET        #0x7,(DSAlertRect)              | mark rect as initialized
    RTS                                         | return from SET_DEFAULT_RECT
| ----------------------------------------------------------
|
| REPOS_ALERT_PORT - reposition port to existing alert rect
|
REPOS_ALERT_PORT:
    BSR.B       DRAW_ALERT_FRAME                | draw alert box frame
    MOVE.L      (DSAlertRect).W,-(A7)           | push alert rect origin (top, left)
    _MovePortTo                                 | move GrafPort to alert position
    RTS                                         | return from REPOS_ALERT_PORT
| ----------------------------------------------------------
|
| DRAW_ALERT_FRAME - draw DS alert box frame (double-bordered rectangle)
|
| Draws the standard system error alert box: erase, frame,
| then inset by 3 pixels and draw a thicker (2x2) inner frame.
DRAW_ALERT_FRAME:
    MOVE.L      A0,-(A7)                        | push rect for EraseRect
    MOVE.L      A0,-(A7)                        | push rect for FrameRect
    MOVE.L      A0,-(A7)                        | push rect for InsetRect (inner)
    MOVE.L      A0,-(A7)                        | push rect for FrameRect (inner)
    MOVE.L      A0,-(A7)                        | push rect for InsetRect (restore)
    _EraseRect                                  | erase alert background
    _FrameRect                                  | draw outer border (1-pixel)
    MOVE.L      #0x20002,-(A7)                  | pen size (2, 2)
    _PenSize                                    | set pen for inner frame
    MOVE.L      #0x30003,-(A7)                  | inset (3, 3)
    _InsetRect                                  | shrink rect for inner frame
    _FrameRect                                  | draw inner border (2-pixel)
    MOVE.L      #0xFFFDFFFD,-(A7)               | inset (-3, -3) = expand back
    _InsetRect                                  | restore rect to original size
    _PenNormal                                  | reset pen to (1, 1)
DRAW_FRAME_RTS:
    RTS                                         | return from DRAW_FRAME_RTS
| ----------------------------------------------------------
|
| SHOW_ALERT_BTNS - display DS alert buttons and wait for mouse click
|
| Looks up button definition in alert table, draws rounded-rect
| buttons with labels, then waits for mouse click on a button.
| Returns Z=0 and A0=button handler if clicked, Z=1 if no buttons.
| ----------------------------------------------------------
| SHOW_ALERT_BTNS - draw buttons and track mouse clicks
| D0 = button definition ID. Draws rounded-rect buttons with
| labels, shows cursor, waits for click, tracks button highlight.
| Returns Z=0 + A0=handler if button clicked, Z=1 if no buttons.
SHOW_ALERT_BTNS:
    BSR.W       LOOKUP_ALERT_ID                 | look up button definition
    BEQ.B       DRAW_FRAME_RTS                  | not found: return Z=1
    MOVEA.L     A0,A2                           | A2 = save button data base
    MOVE.W      (A0)+,D3                        | D3 = button count
    MOVEA.L     A0,A3                           | A3 = first button entry
| Draw each button: label text + rounded-rect frame
DRAW_BTN_LOOP:
    MOVE.L      0x2(A3),-(A7)                   | push button rect top-left
    ADDI.L      #0xE0004,(A7)                   | offset text pos: Y+14, X+4
    _MoveTo                                     | move pen to text position
    MOVE.W      (A3),D0                         | D0 = button label string ID
    BSR.W       LOOKUP_ALERT_ID                 | look up label string
    SUBQ.W      #0x1,A0                         | back up to Pascal length byte
    MOVE.L      A0,-(A7)                        | push Pascal string ptr
    _DrawString                                 | draw button label
    PEA.L       0x2(A3)                         | push button rect
    MOVE.L      #0x100010,-(A7)                 | push oval size (16, 16)
    _FrameRoundRect                             | frame button as rounded rect
    ADDA.W      #0xC,A3                         | advance to next button (12 bytes)
    SUBQ.W      #0x1,D3                         | decrement button counter
    BNE.B       DRAW_BTN_LOOP                   | more buttons: draw next
| All buttons drawn: show cursor and wait for mouse click
    MOVEA.L     (A5),A0                         | A0 = QD globals
    PEA.L       -0x6C(A0)                       | push arrow cursor data
    _SetCursor                                  | set cursor to arrow
    _ShowCursor                                 | show cursor
    MOVE.W      #0x2000,SR                      | enable interrupts (IPL=0)
    ST.B        (CrsrCouple).W                  | enable cursor tracking
    CLR.B       (VBLQueueHdr_Flags).W           | reset VBL queue flags
| Wait for mouse button down
WAIT_MOUSE_DOWN:
    TST.B       (MBState).W                     | mouse button up (bit 7)?
    BNE.B       WAIT_MOUSE_DOWN                 | yes: keep waiting
| Mouse down: find which button was clicked
    MOVEA.L     A2,A3                           | A3 = button data base
    MOVE.W      (A3)+,D3                        | D3 = button count
    ADDQ.W      #0x2,A3                         | skip past count + first label ID
HITTEST_BTN_LOOP:
    BSR.B       BTN_PT_IN_RECT                  | is mouse in this button?
    BNE.B       TRACK_BTN_DOWN                  | yes: track this button
    ADDA.W      #0xC,A3                         | no: advance to next button
    SUBQ.W      #0x1,D3                         | decrement button counter
    BNE.B       HITTEST_BTN_LOOP                | more buttons: test next
    BRA.B       WAIT_MOUSE_DOWN                 | click outside all buttons: wait
| Mouse is on a button: highlight it and track while held
TRACK_BTN_DOWN:
    BSR.B       BTN_INVERT                      | invert button (highlight)
    MOVEQ.L     #0x1,D3                         | D3 = 1 (currently highlighted)
TRACK_BTN_LOOP:
    BSR.B       BTN_PT_IN_RECT                  | still inside button?
    CMP.B       D0,D3                           | highlight state matches position?
    BEQ.B       TRACK_BTN_CHECK                 | yes: no change needed
    EORI.W      #0x1,D3                         | toggle highlight state
    BSR.B       BTN_INVERT                      | invert button (toggle visual)
TRACK_BTN_CHECK:
    TST.B       (MBState).W                     | mouse still down?
    BEQ.B       TRACK_BTN_LOOP                  | yes: keep tracking
    TST.B       D3                              | released inside button?
    BEQ.B       WAIT_MOUSE_DOWN                 | no (highlight off): wait again
    MOVE.W      0x8(A3),D0                      | D0 = button action ID
    BSR.W       LOOKUP_ALERT_ID                 | look up action handler
    RTS                                         | return Z=0, A0=handler
| ----------------------------------------------------------
|
| BTN_PT_IN_RECT - test if mouse is inside button rect at A3
|
| Returns D0 nonzero if mouse point is inside the rect.
BTN_PT_IN_RECT:
    SUBQ.W      #0x2,A7                         | room for Boolean result
    MOVE.L      (Mouse_v).W,-(A7)               | push mouse position (v, h)
    MOVE.L      A3,-(A7)                        | push button rect ptr
    _PtInRect                                   | test if point is in rect
    MOVE.B      (A7)+,D0                        | D0 = result (NZ = inside)
    RTS                                         | return from BTN_PT_IN_RECT
| ----------------------------------------------------------
|
| BTN_INVERT - invert (highlight/unhighlight) button at A3
|
BTN_INVERT:
    MOVE.L      A3,-(A7)                        | push button rect
    MOVE.L      #0x100010,-(A7)                 | push oval size (16, 16)
    _InvertRoundRect                            | XOR button area (toggle highlight)
    RTS                                         | return from BTN_INVERT
