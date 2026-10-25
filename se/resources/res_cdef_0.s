| =========================================================================
| CDEF 0 -- the standard button control definition function: push buttons,
| check boxes and radio buttons (Apple: PushButProc, ButtonCDEF.a)
| =========================================================================
| ROM offsets +0x37A28..+0x37D51: the 8-byte header of the ROM resource at
| +0x37A28, then the resource data, 802 bytes from +0x37A30 (_CDEF_0_ in
| MacSEROM.lst) on; type CDEF, ID 0, no name, attributes $58 (resSysHeap,
| resLocked, resProtected). The same in both SE ROMs. (The Mac Plus ROM
| has no CDEFs; it uses those of the System file.)
|
| Version: the defproc header says version 4 -- Inside Macintosh IV-53's
| "version 4 or greater" CDEF with multi-line titles. Against the change
| history of Apple's ButtonCDEF.a (System 7.1 sources, version 11) this is
| the code of Andy Hertzfeld (1982-83) with EHB's changes of 1985:
|   5/16/85  HitPBut returns 254 only if the point is in the control
|   5/20/85  multi-line titles, the lines separated by CR ($0D)
|   8/26/85  variable-sized system font (SysFontSize, FMDefaultSize)
| and none of the changes of 1986-87: no color (C59, C203, C700: no
| auxiliary control color tables, RGBForeColor/RGBBackColor, txMode),
| no right-to-left check boxes (teSysJust, C560), and CalcPBut still
| locks the control with BSET instead of HLock (C424). Later additions
| are missing as well: messages 10/11 of the 32-bit clean Control
| Manager (1989), gray text and PaintRoundRect in DisableText (1990),
| locking the control while drawing (1990-91).
|
| Calling convention (Pascal, IM I-328):
|   FUNCTION PushButProc(varCode: INTEGER; theControl: ControlHandle;
|                        message: INTEGER; param: LONGINT): LONGINT;
| The Control Manager (NEWCONTROL_FOUND in toolbox/control_mgr.s) clears
| the result, pushes the variation code (the high byte of the
| contrlDefHandle field), the control handle, the message and param,
| locks the CDEF and calls it with thePort set to the control's window;
| the defproc pops its 12 bytes of parameters. Stack frame (from A6):
|   +20 function result  +18 varCode  +14 theControl  +12 message
|   +8 param  -20 SavePen: the caller's pen state, restored on exit;
|   -30..-21 not used here (Apple's IndicatorRect, used by CDEF 1)
|
| Variation code (procID = 16 * resource ID + variation; IM I-315, I-328):
|   bits 0-2  0 = pushButProc, 1 = checkBoxProc, 2 = radioButProc
|   bit 3     useWFont: title in the window's font; otherwise the system
|             font (txFont 0, plain) in size SysFontSize (FMDefaultSize
|             if that is 0)
|
| Messages (IM I-329..I-332); the dispatcher ignores all but 0-2:
|   0 drawCntl   DrawPBut   param low byte = part to draw; the whole
|                           control is drawn, but a check box or radio
|                           button is erased first only for 0
|   1 testCntl   HitPBut    param = point; result inButton (10) or
|                           inCheckBox (11; check boxes and radio
|                           buttons), 254 for contrlHilite 254, else 0
|   2 calcCRgns  CalcPBut   param = region handle: the rounded rectangle
|                           of a push button, contrlRect of a check box
|                           or radio button; DragPattern := gray
|
| Appearance: a push button is a rounded rectangle (corner ovals half as
| high as the button) with each title line centered; a check box (radio
| button) is a 12 x 12 square (circle) 2 pixels from the left edge,
| centered vertically, with the title 18 pixels from the left edge.
| contrlHilite 0 = normal; 1-253 = hilited (push button inverted, box
| framed with a 2 x 2 pen); 254, 255 = inactive (DisableText dims the
| control with the gray pattern in patBic mode). contrlValue bit 0 =
| checked: an X in the check box, a filled circle in the radio button.
|
| Registers in the message routines: A3 = control handle, A0 = control
| pointer (on entry), D3 = param, D6 = variation code AND 7, D7 =
| variation code, D4 = corner oval size (RoundCalc, in DrawPBut and
| CalcPBut).
|
| Known problem (fixed by Apple in 1990-91, ButtonCDEF.a <4> and <14>):
| the control record is not locked while DrawPBut runs -- the Control
| Manager locks only the CDEF --, yet A2 (contrlTitle) and A4 (contrlRect)
| point into it while _GetFontInfo, _TextWidth and _DrawText run; when
| one of these has to load a font, the heap can be compacted and the
| record moved, and the code goes on with stale pointers (DisableText
| even insets the rectangle in place).
|
| Sources: Mac OS 7.1 Toolbox/ControlMgr/ButtonCDEF.a (Apple's routine and
| label names, its comments where the code is the same), Inside Macintosh
| I "The Control Manager" and IV-53.
| =========================================================================

| Stack frame of PushButProc (offsets from A6 after the LINK)
.set CDEF0_PARAM, 8                             | param (long)
.set CDEF0_MESSAGE, 12                          | message (word)
.set CDEF0_CTLHNDL, 14                          | theControl (ControlHandle)
.set CDEF0_VARCODE, 18                          | varCode (word)
.set CDEF0_RESULT, 20                           | function result (long)
.set CDEF0_SAVEPEN, -20                         | SavePen: caller's PenState (18 bytes)
.set CDEF0_FRAMESIZE, -30                       | FrameSize: size of the locals

| -------------------------------------------------------------------------
| ROM resource header: a block header in the format of the Memory
| Manager's (tag and physical block size, then a relative-handle field) in
| front of the resource data, as for every ROM resource. The second long
| counts up in steps of 4 from one ROM resource to the next ($54 for
| PACK 5, the first).
| -------------------------------------------------------------------------
Resource_CDEF_0000:
Resource_CDEF_0000_Header:
        .long   0xC000032A                      | ROM resource header: tag $C0, physical size $32A (8 + $322)
        .long   0x00000080                      | relative handle: master pointer at ROM zone + $80

| -------------------------------------------------------------------------
| Entry point and Apple's standard defproc header: a branch around it,
| flags, resource type, resource ID and version number.
| -------------------------------------------------------------------------
CDEF0_ENTRY:
_CDEF_0_:
        BRA.B   CDEF0_START                     | skip header
        .short  0x0000                          | flags
        .ascii  "CDEF"                          | resource type
        .short  0x0000                          | resource ID 0
        .short  0x0004                          | version 4

| -------------------------------------------------------------------------
| PushButProc -- save the registers and the pen state, fetch the
| parameters and dispatch on the message through GoPushBut.
| -------------------------------------------------------------------------
CDEF0_START:
        LINK    A6,#CDEF0_FRAMESIZE             | set up a stack frame to address parameters
        MOVEM.L D3-D7/A1-A4,-(SP)               | save work registers
        CMPI.W  #0x3,CDEF0_MESSAGE(A6)          | drawCntl, testCntl or calcCRgns?
        BGE.W   CDEF0_DONEP1                    | no (3-8): nothing to do, result 0
        PEA.L   CDEF0_SAVEPEN(A6)               | push pointer to savePenState
        _GetPenState                            | remember current penState
        _PenNormal                              | set the pen the way we want it
        LEA.L   CDEF0_PARAM(A6),A0              | get ptr to first parameter
        MOVE.L  (A0)+,D3                        | get param in D3
        MOVE.W  (A0)+,D0                        | get message
        MOVEA.L (A0)+,A3                        | get the control handle
        MOVE.W  (A0)+,D6                        | get selection index (variation code)
        MOVE.W  D6,D7                           | remember raw selection code
        ANDI.W  #0x7,D6                         | strip high part: 0 button, 1 box, 2 radio
        CLR.L   (A0)                            | clear out function result
        MOVEA.L (A3),A0                         | get control pointer in A0
        ADD.W   D0,D0                           | double for word index
        LEA.L   CDEF0_GOPUSHBUT(PC),A1          | get table address
        ADDA.W  0x0(A1,D0.W),A1                 | compute dispatch address
        JSR     (A1)                            | dispatch: DrawPBut, HitPBut or CalcPBut
        PEA.L   CDEF0_SAVEPEN(A6)               | push savePenState
        _SetPenState                            | restore original pen state
| we're done -- restore registers and return to caller
CDEF0_DONEP1:
        MOVEM.L (SP)+,D3-D7/A1-A4               | restore work registers
        UNLK    A6                              | unlink stack frame
        MOVEA.L (SP)+,A0                        | get return address
        ADDA.W  #0xC,SP                         | strip parameters
        JMP     (A0)                            | return to caller

| GoPushBut -- dispatch table: offsets of the message routines from the
| table, indexed by message * 2
CDEF0_GOPUSHBUT:
        .short  CDEF0_DRAWPBUT-CDEF0_GOPUSHBUT  | draw is message 0
        .short  CDEF0_HITPBUT-CDEF0_GOPUSHBUT   | hit test is message 1
        .short  CDEF0_CALCPBUT-CDEF0_GOPUSHBUT  | calc regions is message 2
| ButStub -- DrawPBut's exit for an invisible control
CDEF0_BUTSTUB:
        RTS                                     | invisible: nothing to draw

| -------------------------------------------------------------------------
| DrawPBut -- message 0 (drawCntl): draw the push button, check box or
| radio button with its title and hilite state.
|   D3 (in)  low byte: the part to draw; the whole control is drawn
|            anyway, but a check box or radio button is erased first
|            only for 0 (avoids flashing when it is hilited or checked)
|   A0 (in)  control pointer; A3 control handle, D6/D7 variation code
| The title (lines separated by CR) is drawn in the window's font for
| variation codes 8 and up (useWFont), otherwise in the system font in
| size SysFontSize (FMDefaultSize if that is 0, 12 on the 64K ROM), and
| clipped to contrlRect intersected with the port's clipRgn; font, size
| and clipRgn are restored afterwards. A push button is framed and,
| depending on contrlHilite, inverted or dimmed; check boxes and radio
| buttons continue in PlotCheck. Changes D0-D7/A0-A2/A4.
| -------------------------------------------------------------------------
CDEF0_DRAWPBUT:
        TST.B   contrlVis(A0)                   | is it visible?
        BEQ.B   CDEF0_BUTSTUB                   | if not, we're done
        BSR.W   CDEF0_ROUNDCALC                 | compute roundNess factor in D4
        LEA.L   contrlRect(A0),A4               | get pointer to bounding rect
        TST.B   D6                              | is it a pushButton?
        BEQ.B   CDEF0_ERASECBOUND               | push buttons are always erased
        TST.B   D3                              | draw all?
        BNE.B   CDEF0_SKIPCERASE                | if not, don't bother to erase
CDEF0_ERASECBOUND:
        MOVE.L  A4,-(SP)                        | push rect
        MOVE.L  D4,-(SP)                        | push rounding factor
        _EraseRoundRect                         | paint it the background color
| save the current font and force the system font
CDEF0_SKIPCERASE:
        MOVEA.L (A5),A0                         | get GrafGlobals base
        MOVEA.L (A0),A0                         | get current port (thePort)
        MOVE.L  0x44(A0),-(SP)                  | remember the font,face (txFont, txFace)
        MOVE.W  0x4A(A0),-(SP)                  | remember the size (txSize)
        SUBQ.W  #0x8,D7                         | was code 8 or greater?
        BGE.B   CDEF0_DRAWPBUT_GOTFONT          | if so, use window's font
        CLR.L   0x44(A0)                        | force system font, normal face
        MOVE.W  #0xC,D0                         | size 12 on the 64K ROM
        TST.W   (ROM85).W                       | 64K ROM (ROM85 negative)?
        BMI.B   CDEF0_DRAWPBUT_GOTSIZE          | yes: use 12
        MOVE.W  (SysFontSize).W,D0              | get default size
        BNE.B   CDEF0_DRAWPBUT_GOTSIZE          | => it's not 0
        MOVE.B  (FMDefaultSize).W,D0            | get default size
CDEF0_DRAWPBUT_GOTSIZE:
        MOVE.W  D0,0x4A(A0)                     | set size of font (txSize)
| save old clip region and clip to the bounding rectangle sected with oldClip
CDEF0_DRAWPBUT_GOTFONT:
        MOVE.L  0x1C(A0),-(SP)                  | push thePort's clipRgn (SectRgn srcRgnA)
        CLR.L   -(SP)                           | make space for region handle
        _NewRgn                                 | allocate a region
        MOVEA.L (SP),A2                         | remember region but leave on stack
        _GetClip                                | remember the current clipRgn
        MOVEA.L (A3),A0                         | get control pointer
        PEA.L   contrlRect(A0)                  | push pointer to its bounding rect
        _ClipRect                               | make that the clipping region
        MOVE.L  A2,-(SP)                        | push the old ClipRgn
        MOVE.L  0x4(SP),-(SP)                   | the answer goes into current clip (dstRgn)
        _SectRgn                                | intersect new and old
| Save off some registers for mondo button title calculations, then set
| them up for our use
        MOVEM.L D4/A2-A3,-(SP)                  | save rounding, old clip, control handle
        MOVEA.L (A3),A0                         | get pointer to control
        LEA.L   contrlTitle(A0),A2              | get title into A2
        LEA.L   contrlRect(A0),A4               | get rect into A4
        MOVEQ.L #0x0,D7                         | clear D7 for the string index
        MOVE.B  (A2),D7                         | get string length into D7
        BEQ.W   CDEF0_NOTITLE                   | quick check for nothing
| now count the number of lines in the title. Lines are separated by CR's
        MOVEQ.L #0x0,D4                         | save number of lines in D4
CDEF0_DRAWPBUT_COUNT:
        ADDQ.W  #0x1,D4                         | count next line
        BSR.W   CDEF0_PT2NEXT                   | point to next line (index in D7)
        TST.B   D7                              | D7 < 0 if done
        BPL.B   CDEF0_DRAWPBUT_COUNT            | => get next line
        MOVE.B  (A2),D7                         | get string length back
| now get a font info record on stack, pointer to it in A3
        SUBQ.W  #0x8,SP                         | make room for 4 INTEGERS
        MOVEA.L SP,A3                           | save pointer in A3
        MOVE.L  A3,-(SP)                        | push pointer to record
        _GetFontInfo                            | and fill the record
| Set up D5 to point to the baseline of the last line
        BSR.W   CDEF0_GETHEIGHT                 | get height of line into D0
        MULU.W  D4,D0                           | #lines times height
        MOVE.W  0x4(A4),D1                      | get bottom of rect
        MOVE.W  D1,D5                           | D5 will be baseline
        SUB.W   (A4),D1                         | get height of rect (- top)
        SUB.W   D0,D1                           | get unused space
        ASR.W   #0x1,D1                         | and DIV by 2
        SUB.W   D1,D5                           | move up from bottom
        SUB.W   0x6(A3),D5                      | to bottom of descender (- leading)
        SUB.W   0x2(A3),D5                      | to the baseline (- descent)
| draw the lines from the last one up: get the width of the current line
| into D0
CDEF0_DONEXTLINE:
        BSR.W   CDEF0_PT2NEXT                   | next line in D7, len in D3
        CLR.W   -(SP)                           | make room for result
        MOVE.L  A2,-(SP)                        | push title pointer
        MOVE.W  D7,D0                           | get our offset into string
        ADDQ.B  #0x2,D0                         | bump past length (or CR)
        MOVE.W  D0,-(SP)                        | push true offset into string
        MOVE.W  D3,-(SP)                        | push number of bytes
        _TextWidth                              | get the string's width
        MOVE.W  (SP)+,D0                        | and save result in D0
| if it's a checkbox, don't center it, just move to right a little
        TST.B   D6                              | is it a check box?
        BEQ.B   CDEF0_ELCENTRO                  | => no, go center the string
        MOVE.W  0x2(A4),D1                      | get the left edge
        ADDI.W  #0x12,D1                        | leave room for check box (18)
        BRA.B   CDEF0_DRAWBTITLE                | back to common code
| center the line in the rect
CDEF0_ELCENTRO:
        MOVE.W  0x6(A4),D1                      | get the right edge
        SUB.W   0x2(A4),D1                      | get the width (- left)
        SUB.W   D0,D1                           | subtract string's width
        ASR.W   #0x1,D1                         | get centering offset
        ADD.W   0x2(A4),D1                      | and add into left
CDEF0_DRAWBTITLE:
        MOVE.W  D1,-(SP)                        | push horizontal position
        MOVE.W  D5,-(SP)                        | and vertical position
        _MoveTo                                 | move the pen there
        MOVE.L  A2,-(SP)                        | point to string
        MOVE.W  D7,D0                           | get our offset into string
        ADDQ.B  #0x2,D0                         | bump past length (or CR)
        MOVE.W  D0,-(SP)                        | push true offset into string
        MOVE.W  D3,-(SP)                        | push length in bytes
        _DrawText                               | this is where we draw the line
| bump baseline point up to next line, test for end
        BSR.B   CDEF0_GETHEIGHT                 | get line height into D0
        SUB.W   D0,D5                           | go up to next base line
        TST.B   D7                              | done yet?
        BPL.B   CDEF0_DONEXTLINE                | => nope
        ADDQ.W  #0x8,SP                         | strip font record
CDEF0_NOTITLE:
        MOVEM.L (SP)+,D4/A2-A3                  | and all those registers
| restore original font, face and size
        MOVEA.L (A5),A0                         | get GrafGlobals base
        MOVEA.L (A0),A0                         | get current port
        MOVE.W  (SP)+,0x4A(A0)                  | restore the size (txSize)
        MOVE.L  (SP)+,0x44(A0)                  | restore the font,face (txFont, txFace)
        TST.B   D6                              | is it a checkBox?
        BNE.W   CDEF0_PLOTCHECK                 | if so, go draw it
        MOVE.L  A4,-(SP)                        | push the rectangle pointer
        MOVE.L  D4,-(SP)                        | push rounding factor
        _FrameRoundRect                         | frame the button
| hilite the button if necessary
        MOVEA.L (A3),A0                         | get control pointer
        MOVE.B  contrlHilite(A0),D0             | is it hilited?
        BEQ.B   CDEF0_DONEDRWBUT                | if not, we're done
        CMPI.B  #0xFE,D0                        | is it the special hilite state (254, 255)?
        BCC.B   CDEF0_SPECIALHILITE             | if so, go do it
        MOVE.L  A4,-(SP)                        | push rectangle
        MOVE.L  D4,-(SP)                        | push rounding factor
        _InvertRoundRect                        | hilite by inverting
| restore original clipping region and we're done
CDEF0_DONEDRWBUT:
        _PenNormal                              | set the pen back to normal
        MOVE.L  A2,-(SP)                        | push old clip region
        _SetClip                                | restore it
        MOVE.L  A2,-(SP)                        | dispose of temporary region
        _DisposeRgn                             | de-allocate it
        RTS                                     | all done!

| -------------------------------------------------------------------------
| Pt2Next -- point to the next line within the title, going backwards
| from the end of the title.
|   A2 (in)   title pointer (Pascal string)
|   D7 (in)   offset of the last character of the next line to do
|   D7 (out)  offset of the line's CR (or of the length byte) - 1: the
|             line starts at D7 + 2; negative (as a byte) after the
|             first line, i.e. if this was the last line to do
|   D3 (out)  length of the line
| D7 is tested as a signed byte: a title with a CR beyond offset 128 is
| cut off there (lines before it are neither counted nor drawn).
| Called by: CDEF0_DRAWPBUT (counting the lines, then for each line)
| -------------------------------------------------------------------------
CDEF0_PT2NEXT:
        MOVEQ.L #0x0,D3                         | clear out count
        TST.B   D7                              | pointing at count?
        BEQ.B   CDEF0_PT2NEXT_DONE              | => yes, a leading CR
CDEF0_PT2NEXT_LOOP:
        CMPI.B  #0xD,0x0(A2,D7.W)               | is char a CR?
        BEQ.B   CDEF0_PT2NEXT_DONE              | => yes, all done
        ADDQ.W  #0x1,D3                         | else bump count by one
        SUBQ.B  #0x1,D7                         | and move back in string
        BNE.B   CDEF0_PT2NEXT_LOOP              | => not end of string
CDEF0_PT2NEXT_DONE:
        SUBQ.B  #0x1,D7                         | prepare for next string
        RTS                                     | D7 < 0 if last line

| -------------------------------------------------------------------------
| GetHeight -- return in D0 the height of one line.
|   A3 (in)   FontInfo record
|   D0 (out)  line height = ascent + descent + leading
| Called by: CDEF0_DRAWPBUT (before and after each line)
| -------------------------------------------------------------------------
CDEF0_GETHEIGHT:
        MOVEQ.L #0x0,D0                         | clear out height
        ADD.W   (A3),D0                         | height = ascent (FontInfo.ascent)
        ADD.W   0x2(A3),D0                      | + descent
        ADD.W   0x6(A3),D0                      | + leading
        RTS                                     | return the line height in D0

| SpecialHilite -- contrlHilite 254 or 255: dim the push button
CDEF0_SPECIALHILITE:
        BSR.B   CDEF0_DISABLETEXT               | gray out the button
        BRA.B   CDEF0_DONEDRWBUT                | restore the clip and return

| -------------------------------------------------------------------------
| DisableText -- dim an inactive control: paint contrlRect, inset by 3
| pixels horizontally and 1 vertically (inside a push button's frame),
| with the gray pattern in patBic mode, which clears every other pixel
| of the title (and of anything else drawn there so far).
|   A4 (in)   contrlRect in the control record: it is inset in place and
|             then restored
| Changes D0-D2/A0-A1 (traps). (Apple's version of 1990 insets by 1, 1
| and paints a rounded rectangle.)
| Called by: CDEF0_SPECIALHILITE (push buttons), CDEF0_PLOTCHECK
| -------------------------------------------------------------------------
CDEF0_DISABLETEXT:
        MOVE.L  A4,-(SP)                        | push rectangle
        MOVE.L  #0x00010003,-(SP)               | dv = 1, dh = 3
        _InsetRect                              | inset contrlRect
        MOVE.L  A4,-(SP)                        | push rectangle (for PaintRect)
        MOVEA.L (A5),A0                         | get QuickDraw globals
        PEA.L   -0x18(A0)                       | push gray (QuickDraw global)
        _PenPat                                 | pen pattern = gray
        MOVE.W  #0xB,-(SP)                      | patBic
        _PenMode                                | pen mode = patBic
        _PaintRect                              | gray it out
        _PenNormal                              | pen back to normal
        MOVE.L  A4,-(SP)                        | push rectangle
        MOVE.L  #0xFFFFFFFD,-(SP)               | dv = -1, dh = -3
        _InsetRect                              | restore contrlRect
        RTS                                     | return from DisableText

| -------------------------------------------------------------------------
| RoundCalc calculates the rounding factor in D4 based on the control's
| rect.
|   A0 (in)   control pointer
|   D6 (in)   variation code AND 7
|   D4 (out)  oval width (high word) and height (low word) of the
|             corners for the RoundRect calls: half the height of
|             contrlRect; 0 for check boxes and radio buttons
| Changes D0. Called by: CDEF0_DRAWPBUT, CDEF0_CALCPBUT
| -------------------------------------------------------------------------
CDEF0_ROUNDCALC:
        TST.B   D6                              | is it a checkBox?
        BNE.B   CDEF0_CHECKROUND                | if so, special case it
        MOVE.W  contrlRect+0x4(A0),D4           | get bottom coordinate
        SUB.W   contrlRect(A0),D4               | figure out vertical height (- top)
        LSR.W   #0x1,D4                         | scale it down by a factor of 2
        MOVE.W  D4,D0                           | fill both halves with it
        SWAP    D4                              | get in high part
        MOVE.W  D0,D4                           | and in low part
        RTS                                     | return the rounding in D4
CDEF0_CHECKROUND:
        MOVEQ.L #0x0,D4                         | checkBoxes are square!
        RTS                                     | return D4 = 0

| -------------------------------------------------------------------------
| HitPBut -- message 1 (testCntl): the button hit test.
|   D3 (in)   the point, in local coordinates of the window
| Result (low word of the function result): 0 if contrlHilite is 255 or
| the point is outside contrlRect; 254 if contrlHilite is 254; else
| inButton (10) for a push button, inCheckBox (11) for a check box or
| radio button. Changes D0-D2/D4/A0-A1.
| -------------------------------------------------------------------------
CDEF0_HITPBUT:
        MOVE.B  contrlHilite(A0),D4             | get hiliteState
        ADDQ.B  #0x1,D4                         | is it 255?
        BEQ.B   CDEF0_HITPBUT_DONE              | if so, skip
        CLR.W   -(SP)                           | make room for function result
        MOVE.L  D3,-(SP)                        | push the point
        PEA.L   contrlRect(A0)                  | push address of rect
        _PtInRect                               | in the rectangle?
        TST.B   (SP)+                           | examine result
        BEQ.B   CDEF0_HITPBUT_DONE              | if not, we're done
        ADDQ.B  #0x1,D4                         | 254 hiliting?
        BEQ.B   CDEF0_RETURN254                 | => say it is so
        MOVE.W  #inButton,CDEF0_RESULT+2(A6)    | return that it was
        TST.B   D6                              | a checkBox?
        BEQ.B   CDEF0_HITPBUT_DONE              | if not, we're done
        ADDQ.W  #0x1,CDEF0_RESULT+2(A6)         | if so, flag it (inCheckBox)
CDEF0_HITPBUT_DONE:
        RTS                                     | return from HitPBut
CDEF0_RETURN254:
        MOVE.W  #0xFE,CDEF0_RESULT+2(A6)        | indicate its 254-disabled
        RTS                                     | return 254

| -------------------------------------------------------------------------
| CalcPBut -- message 2 (calcCRgns): return the bounding region of the
| button.
|   D3 (in)   handle of the region to set (buttons have no indicator:
|             the Control Manager never sets the high bit here)
| A push button's region is its rounded rectangle, recorded with
| OpenRgn/FrameRoundRect/CloseRgn while the control record is locked --
| by setting the lock bit of its master pointer (Apple's version of
| 11/18/86, C424, calls HLock/HUnlock) -- because the rectangle is
| passed by address; a check box's or radio button's is contrlRect.
| Both set DragPattern to gray (DragGray). Changes D0-D2/D4/A0-A1.
| -------------------------------------------------------------------------
CDEF0_CALCPBUT:
        TST.B   D6                              | is it a checkBox?
        BNE.B   CDEF0_CALCSQUARE                | check box bounds are just rects
        BSR.B   CDEF0_ROUNDCALC                 | calculate rounding factor
        _HidePen                                | dont draw anything
        _OpenRgn                                | start recording the region
        BSET    #0x7,(A3)                       | lock the control handle (master pointer bit 7)
        MOVEA.L (A3),A0                         | get pointer to control
        PEA.L   contrlRect(A0)                  | push rectangle pointer
        MOVE.L  D4,-(SP)                        | push rounding factor
        _FrameRoundRect                         | frame the button
        MOVE.L  D3,-(SP)                        | push the region
        _CloseRgn                               | make the rounded rectangular region
        _ShowPen                                | pen visible again
        BCLR    #0x7,(A3)                       | unlock the control (even if locked before)
| set the pattern for indicator dragging
CDEF0_DRAGGRAY:
        MOVEA.L (A5),A0                         | get qDraw globals
        LEA.L   -0x18(A0),A0                    | point to gray pattern
        MOVE.L  (A0)+,(DragPattern).W           | move in the 1st half
        MOVE.L  (A0),(DragPattern+4).W          | move in the 2nd half
        RTS                                     | all done!
CDEF0_CALCSQUARE:
        MOVE.L  D3,-(SP)                        | push the region
        PEA.L   contrlRect(A0)                  | push the rectangle pointer
        _RectRgn                                | make a rectangular region
        BRA.B   CDEF0_DRAGGRAY                  | all done -- go set drag pattern

| -------------------------------------------------------------------------
| PlotCheck takes care of drawing the actual check box of the check box
| button. It figures out where to draw the box, draws it, and then checks
| it or not based on the current value and hilite state of the button
| (DrawPBut's tail for check boxes and radio buttons).
|   A4 (in)   contrlRect; A3 control handle, A2 the saved clipRgn
| The box is 12 x 12, 2 pixels from the left edge of contrlRect and
| centered vertically; it is erased, then for contrlHilite 254/255 the
| control is dimmed (DisableText), for 1-253 the box is framed with a
| 2 x 2 pen; framed as a square (check box) or circle (radio button);
| if contrlValue bit 0 is set: an X through the box (corner to corner)
| or a circle inset by 3, painted. Ends in DoneDrwBut.
| -------------------------------------------------------------------------
CDEF0_PLOTCHECK:
        SUBQ.W  #0x8,SP                         | allocate a rectangle on the stack
        MOVE.W  0x4(A4),D0                      | D0 = bottom of contrlRect
        MOVE.W  D0,D1                           | save a copy
        SUB.W   (A4),D0                         | get height (- top)
        SUBI.W  #0xC,D0                         | sub box height (12)
        ASR.W   #0x1,D0                         | div by 2
        SUB.W   D0,D1                           | get offset from bottom
        MOVE.W  D1,0x4(SP)                      | set up the bottom
        SUBI.W  #0xC,D1                         | compute the top
        MOVE.W  D1,(SP)                         | set up the top
        MOVE.W  0x2(A4),D1                      | get left edge of boundsRect
        ADDQ.W  #0x2,D1                         | indent 2 pixels
        MOVE.W  D1,0x2(SP)                      | that's the left of the checkRect
        ADDI.W  #0xC,D1                         | compute right edge
        MOVE.W  D1,0x6(SP)                      | update the right edge
| erase the check box
        MOVE.L  SP,-(SP)                        | push rectangle pointer
        _EraseRect                              | erase it
| OK, now we must fill in the checkBox rectangle based on the value and
| hilite state of the control
        MOVEA.L (A3),A0                         | get control pointer
        MOVE.W  contrlValue(A0),D5              | get the value
        MOVE.B  contrlHilite(A0),D0             | is it hilited?
        BEQ.B   CDEF0_FRAMECHECK                | if not, skip
        CMPI.B  #0xFE,D0                        | disabled?
        BCS.B   CDEF0_SKIPDIS                   | if not, go double the pen
        BSR.W   CDEF0_DISABLETEXT               | dim the title
        BRA.B   CDEF0_FRAMECHECK                | then frame the box
| its hilited so up the penSize to indicate its hilited
CDEF0_SKIPDIS:
        MOVE.L  #0x00020002,-(SP)               | 2 x 2
        _PenSize                                | up the penSize
CDEF0_FRAMECHECK:
        MOVE.L  SP,-(SP)                        | push the rectangle
        CMPI.B  #0x2,D6                         | test for radio button
        BEQ.B   CDEF0_FRAMECHECK_OVAL           | if its a radio button, go do it
        _FrameRect                              | frame it
        BRA.B   CDEF0_FRAMECHECK_DONE           | go draw the check
CDEF0_FRAMECHECK_OVAL:
        _FrameOval                              | frame the circle
CDEF0_FRAMECHECK_DONE:
        _PenNormal                              | pen back to 1 x 1
| now we can draw the check if we're supposed to
        LSR.W   #0x1,D5                         | check out the low bit of D5
        BCC.B   CDEF0_DONEPCHECK                | if its off, we're done
        CMPI.W  #0x2,D6                         | test for radio button
        BEQ.B   CDEF0_DRAWRBUTTON               | if its a radio button, go do it
        MOVE.L  SP,-(SP)                        | push the rectangle pointer
        MOVE.L  (OneOne).W,-(SP)                | push the inset factor
        _InsetRect                              | inset the rectangle
        MOVE.L  (SP),-(SP)                      | push top left
        _MoveTo                                 | move to it
        MOVE.L  0x4(SP),-(SP)                   | push bottom right
        _LineTo                                 | draw one line of the cross (to bottom right)
        MOVE.W  0x6(SP),-(SP)                   | push right (h)
        MOVE.W  0x2(SP),-(SP)                   | push top (v)
        SUBQ.W  #0x1,(SP)                       | bias the top: v = top - 1
        _MoveTo                                 | move to the upper right corner
        MOVE.W  0x2(SP),-(SP)                   | push left (h)
        SUBQ.W  #0x1,(SP)                       | bias the left: h = left - 1
        MOVE.W  0x6(SP),-(SP)                   | push bottom (v)
        _LineTo                                 | draw the other line, to the lower left corner
        BRA.B   CDEF0_DONEPCHECK                | done with the cross
| draw the radio button check mark -- a little circle
CDEF0_DRAWRBUTTON:
        MOVE.L  SP,-(SP)                        | push pointer to rect
        MOVE.L  #0x00030003,-(SP)               | push inset factor
        _InsetRect                              | inset it
        MOVE.L  SP,-(SP)                        | push rect again
        _PaintOval                              | draw the circle
CDEF0_DONEPCHECK:
        ADDQ.W  #0x8,SP                         | pop off the rectangle
        BRA.W   CDEF0_DONEDRWBUT                | all done!

