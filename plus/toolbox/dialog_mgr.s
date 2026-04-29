| Dialog Manager - Internal Routines
|
| Contains the internal subroutines called by the Dialog Manager's
| public traps (in resource_mgr.s): item initialization from DITL,
| item drawing/disposal, event dispatch, edit field switching,
| hit testing, ParamText substitution, and default button outlining.
|
| Also contains unrelated utility traps that share this ROM region:
| _Munger, _HandToHand, _PtrToXHand, _PtrToHand, _HandAndHand,
| _PtrAndHand, fixed-point math (LongMul, FixMul, FixDiv, FixRatio,
| FixRound, HiWord, LoWord), and MacApp dispatch (StdOpcodeProc).
|
| Key registers used throughout Dialog Manager routines:
| A4 = DialogPtr (pointer to DialogRecord)
| A3 = items handle (DITL resource, from DialogRecord+0x9C)
| A2 = pointer to current item entry within DITL data
| D3 = current item index (0-based; -1 = none/done)
| A6 frame: -0x28(A6) = item display rect (8 bytes)
| -0x4C(A6) = EventRecord copy (for ModalDialog/DialogSelect)
| -0x1C(A6) = local mouse point
|
| DITL item entry layout (variable-length, word-aligned):
| +0: handle/procPtr (4 bytes) - control handle, text handle, or userItem proc
| +4: display rect (8 bytes) - item bounding rectangle
| +12: item type (1 byte) - see ctrlItem/statText/editText/iconItem/picItem
| +13: data length (1 byte) followed by data (padded to even)
|
| References:
| Inside Macintosh Vol I, pp 399-430: The Dialog Manager

| ============================================================
| DITL Item Initialization - called from FINDDITEM_CONT loop in resource_mgr.s
| Decodes item type and loads/creates the appropriate resource or control.
| Entry: A2 = ptr to DITL item entry, D4 = mode (0=init, 1=draw, 2=hitTest)
| A4 = DialogPtr, D0 = item type byte from itmType(A2)
| ============================================================
ENTRY:
        BSR.B   FINDDITEM_CONT_2                | get item handle and type byte into D0
        PEA.L   FINDDITEM_EXIT_2(PC)            | push return addr for FINDDITEM_CONT's item loop
        CMPI    #0x2,D4                         | D4: 0=init, 1=draw, 2=hitTest, 3=updtDraw
        BGT     DLGMGR_FOUND                    | D4>2: hit test item rect vs update rgn
        BEQ     DLGMGR_CONT_24                  | D4=2: dispose item resources
        TST     D4                              | check remaining D4 action codes (0, 1, -1)
        BEQ.B   DLGMGR_CONT_9                   | D4=0: initialize item from DITL data
        BGT     DLGMGR_CONT_17                  | D4=1: draw a single item
        BTST    #0x2,D0                         | D4=-1: load resource for item
        BNE.B   DLGMGR_CONT                     | bit 2 set = ctrlItem, need CNTL/CDEF
        ROXR    #0x7,D0                         | shift iconItem bit (bit 5) into carry
        BMI.B   DLGMGR_CONT_4                   | bit 6 (picItem) set = load ICON resource
        BCS.B   DLGMGR_CONT_5                   | bit 5 (iconItem) set = load PICT resource
        RTS                                     | statText/editText/userItem: no resource

| ----------------------------------------------------------
| Load resource handle for a control item (ctrlItem)
| Determines CNTL vs CDEF resource type from control subtype bits.
| ----------------------------------------------------------
DLGMGR_CONT:
        ANDI    #0x3,D0                         | mask control subtype (btnCtrl..resCtrl)
        CMPI    #0x3,D0                         | resCtrl (3) = control from resource
        BNE.B   DLGMGR_CONT_3                   | btnCtrl/chkCtrl/radCtrl: use CDEF
        PEA.L   DLGMGR_CONT_2(PC)               | push callback to read CNTL's defProc ID
        MOVE.L  #0x434E544C,D1                  | 'CNTL' resource type
        BRA.B   DLGMGR_CONT_6                   | go load 'CNTL' resource using DITL ID

| ----------------------------------------------------------
| DLGMGR_CONT_2 - callback for resCtrl: extract CDEF proc ID from CNTL resource
| ----------------------------------------------------------
DLGMGR_CONT_2:
        MOVE.L  (A2),A1                         | dereference CNTL handle
        MOVE    0x10(A1),D0                     | get contrlVis (CDEF proc ID) from CNTL
DLGMGR_CONT_3:
        MOVE.L  #0x43444546,D1                  | 'CDEF' resource type
        BRA.B   DLGMGR_CONT_7                   | load the CDEF resource

| ----------------------------------------------------------
| Load ICON resource for an iconItem
| ----------------------------------------------------------
DLGMGR_CONT_4:
        MOVE.L  #0x49434F4E,D1                  | 'ICON' resource type
        BRA.B   DLGMGR_CONT_6                   | go load 'ICON' resource using DITL ID

| ----------------------------------------------------------
| Load PICT resource for a picItem
| ----------------------------------------------------------
DLGMGR_CONT_5:
        MOVE.L  #0x50494354,D1                  | 'PICT' resource type
DLGMGR_CONT_6:
        MOVE    0xE(A2),D0                      | get resource ID from DITL item data
DLGMGR_CONT_7:
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  D1,-(SP)                        | push resource type
        MOVE    D0,-(SP)                        | push resource ID
        _GetResource                            | load the requested resource
        MOVE.L  (SP)+,A2                        | A2 = resource handle
        CMPI    #-0x1,D4                        | D4=-1: just loading, check purgeability
        BEQ.B   DLGMGR_CONT_8                   | go check/mark purgeable state
        BCLR    #0x6,(A2)                       | clear handle's purgeable flag for use
        RTS                                     | return with resource handle in A2

| ----------------------------------------------------------
| DLGMGR_CONT_8 - mark handle purgeable if the resource itself is purgeable
| Called with D4=-1 during pre-load to preserve resource's purgeable attr.
| ----------------------------------------------------------
DLGMGR_CONT_8:
        SUBQ.W  #0x2,SP                         | space for GetResAttrs result word
        MOVE.L  A2,-(SP)                        | push resource handle
        _GetResAttrs                            | get resource attributes word
        MOVE    (SP)+,D0                        | pop attributes word into D0
        BTST    #0x5,D0                         | test resPurgeable attribute
        BEQ.B   DLGMGR_NO                       | not purgeable: leave handle flag clear
        BSET    #0x6,(A2)                       | mark master pointer as purgeable
DLGMGR_NO:
        RTS                                     | return from purgeable check

| ----------------------------------------------------------
| Initialize item from DITL data (D4=0)
| A0 = item handle from DITL entry, D0 = item type byte
| If handle already set (non-nil), item was pre-initialized - skip.
| ----------------------------------------------------------
DLGMGR_CONT_9:
        MOVE.L  A0,D1                           | test if item handle already exists
        BEQ.B   DLGMGR_EMPTY                    | nil: need to create from DITL data
        RTS                                     | already initialized, nothing to do

| ----------------------------------------------------------
| Create item handle/control from DITL data based on item type.
| Dispatches by testing type bits: ctrlItem, iconItem, picItem,
| statText/editText.
| ----------------------------------------------------------
DLGMGR_EMPTY:
        BTst    #0x2,D0                         | test ctrlItem bit
        BNE.B   DLGMGR_CONT_14                  | ctrlItem: create control
        ROXR    #0x5,D0                         | shift statText (bit 3) into X/C flags
        BCS.B   DLGMGR_CONT_10                  | statText: copy text data to handle
        BMI.B   DLGMGR_CONT_10                  | editText: copy text data to handle
        ROXR    #0x2,D0                         | shift iconItem/picItem bits
        BMI.B   DLGMGR_CONT_11                  | iconItem: load ICON resource
        BCS.B   DLGMGR_CONT_12                  | picItem: load PICT resource
        RTS                                     | userItem: handle stays nil

| ----------------------------------------------------------
| Initialize statText or editText: copy inline text from DITL to a handle
| DITL item data: length byte at +13(A2), text bytes follow
| ----------------------------------------------------------
DLGMGR_CONT_10:
        LEA.L   0xD(A2),A0                      | point to data length byte in DITL entry
        MOVEQ.L #0x0,D0                         | clear upper bytes of length register
        MOVE.B  (A0)+,D0                        | D0 = text length, A0 -> text data
        _PtrToHand                              | create handle with copy of text
        MOVE.L  A0,-(SP)                        | push text handle (result in A0)
        BRA.B   DLGMGR_CONT_16                  | store handle in item entry

| ----------------------------------------------------------
| Initialize iconItem: load ICON resource by ID from DITL data
| ----------------------------------------------------------
DLGMGR_CONT_11:
        MOVE.L  #0x49434F4E,D0                  | 'ICON' resource type
        BRA.B   DLGMGR_CONT_13                  | go load 'ICON' resource

| ----------------------------------------------------------
| Initialize picItem: load PICT resource by ID from DITL data
| ----------------------------------------------------------
DLGMGR_CONT_12:
        MOVE.L  #0x50494354,D0                  | 'PICT' resource type
DLGMGR_CONT_13:
        SUBQ.W  #0x4,SP                         | space for GetResource handle result
        MOVE.L  D0,-(SP)                        | push resource type
        MOVE    0xE(A2),-(SP)                   | push resource ID from DITL item data
        _GetResource                            | load the 'ICON' or 'PICT' resource
        BRA.B   DLGMGR_CONT_16                  | store resource handle in item entry

| ----------------------------------------------------------
| Initialize ctrlItem: create control from resource or inline data.
| D0 bits 0-1 = subtype: btnCtrl(0), chkCtrl(1), radCtrl(2), resCtrl(3)
| ----------------------------------------------------------
DLGMGR_CONT_14:
        ANDI    #0x3,D0                         | isolate control subtype
        CMPI    #0x3,D0                         | resCtrl?
        BNE.B   DLGMGR_NO_2                     | no: create standard btn/chk/rad control
        SUBQ.W  #0x4,SP                         | space for GetNewControl result
        MOVE    0xE(A2),-(SP)                   | push CNTL resource ID from DITL data
        MOVE.L  A4,-(SP)                        | push owning dialog window
        _GetNewControl                          | create control from CNTL resource
        MOVE.L  (SP),-(SP)                      | push control handle for MoveControl
        MOVE.L  0x4(A2),-(SP)                   | push display rect top-left from DITL
        _MoveControl                            | position control at item's display rect
        BRA.B   DLGMGR_CONT_15                  | go store control handle and validate

| ----------------------------------------------------------
| Create standard button/checkbox/radio control from DITL inline data.
| Builds NewControl params: owner, rect, title, visible, value=1,
| min=0, procID=subtype*16, refCon=0.
| ----------------------------------------------------------
DLGMGR_NO_2:
        SUBQ.W  #0x4,SP                         | space for NewControl result
        MOVE.L  A4,-(SP)                        | push owning window (DialogPtr)
        PEA.L   -0x28(A6)                       | push item display rect
        PEA.L   0xD(A2)                         | push title string (from DITL item data)
        ST.B    -(SP)                           | visible = true ($FF)
        CLR.L   -(SP)                           | value = 0, min = 0
        MOVE    #0x1,-(SP)                      | max = 1
        MOVE    D0,-(SP)                        | procID = subtype (0=pushBut,1=chkBox,2=radio)
        CLR.L   -(SP)                           | refCon = 0
        _NewControl                             | create standard system control
DLGMGR_CONT_15:
        PEA.L   -0x28(A6)                       | validate item rect (no redraw needed)
        _ValidRect                              | validate the item's display rect
DLGMGR_CONT_16:
        MOVE.L  (SP)+,(A2)                      | store new handle into itmHndl field
        RTS                                     | return from item initialization

| ----------------------------------------------------------
| Hit test: check if item rect intersects update region (D4>2)
| Builds a temp rect from item's display rect, insets by -4 pixels
| (to include the 3-pixel frame around editText items), then tests
| intersection with the update region passed in 0x8(A6).
| Returns via BNE to DLGMGR_CONT_18 (which falls into DLGMGR_CONT_17 to draw item).
| ----------------------------------------------------------
DLGMGR_FOUND:
        MOVE.L  0x8(A2),-(SP)                   | push item rect bottom-right
        MOVE.L  0x4(A2),-(SP)                   | push item rect top-left
        MOVE.L  A7,-(SP)                        | push ptr to temp rect on stack
        MOVE.L  #0xFFFCFFFC,-(SP)               | inset by (-4,-4) to include frame
        _InsetRect                              | inset temp rect to include focus frame
        SUBQ.W  #0x2,SP                         | space for RectInRgn boolean result
        PEA.L   0x2(SP)                         | push ptr to temp rect
        MOVE.L  0x8(A6),-(SP)                   | push update region handle
        _RectInRgn                              | does item rect intersect update rgn?
        TST.B   (SP)+                           | check RectInRgn boolean result
        ADDQ.W  #0x8,SP                         | clean up temp rect from stack
        BNE.B   DLGMGR_CONT_18                  | intersects: go draw this item
        RTS                                     | no intersection: skip this item

| ----------------------------------------------------------
| DLGMGR_CONT_17 - Draw a single dialog item (D4=1)
| Dispatches by item type to draw controls, text, icons, pictures,
| or call userItem drawing procedure.
| ----------------------------------------------------------
DLGMGR_CONT_17:
        BSR     FINDDITEM_CONT_2                | get item handle (A0) and type (D0)
        ANDI.B  #0x7F,D0                        | strip itemDisable bit
        BEQ.B   DLGMGR_CONT_19                  | userItem (type 0): call drawing proc
        BSR     DLGMGR_CONT_34                  | check if item rect intersects portRect
        BEQ.B   DLGMGR_SKIP                     | not visible: skip drawing
DLGMGR_CONT_18:
        BSR     FINDDITEM_CONT_2                | re-fetch handle and type for drawing
        BTST    #0x2,D0                         | ctrlItem?
        BNE.B   DLGMGR_SKIP_2                   | controls drawn by DrawControls, skip here
        ROXR    #0x5,D0                         | shift statText/editText bits into flags
        BCS.B   DLGMGR_CONT_22                  | statText: draw text item
        BMI.B   DLGMGR_CONT_22                  | editText: draw text item
        ROXR    #0x2,D0                         | shift iconItem/picItem bits
        BMI.B   DLGMGR_CONT_20                  | iconItem: PlotIcon
        BCS.B   DLGMGR_CONT_21                  | picItem: DrawPicture
DLGMGR_CONT_19:
        MOVE.L  (A2),D0                         | get userItem's drawing proc pointer
        BEQ.B   DLGMGR_SKIP                     | nil proc: nothing to draw
        MOVE.L  A4,-(SP)                        | push DialogPtr as 1st param
        MOVE    D3,-(SP)                        | push 0-based item number
        ADDQ.W  #0x1,(SP)                       | push 1-based item number as 2nd param
        MOVE.L  D0,A0                           | A0 = userItem drawing proc pointer
        JSR     (A0)                            | call userItem drawing procedure
DLGMGR_SKIP:
        RTS                                     | return from userItem drawing

| ----------------------------------------------------------
| Draw iconItem: load and plot icon in item's display rect
| ----------------------------------------------------------
DLGMGR_CONT_20:
        PEA.L   -0x28(A6)                       | push item display rect
        MOVE.L  (A2),-(SP)                      | push icon handle
        MOVE.L  (SP),-(SP)                      | dup handle for LoadResource
        _LoadResource                           | ensure icon data is in memory
        _PlotIcon                               | draw icon in display rect
        RTS                                     | return from icon drawing

| ----------------------------------------------------------
| Draw picItem: load and draw picture in item's display rect
| ----------------------------------------------------------
DLGMGR_CONT_21:
        MOVE.L  (A2),-(SP)                      | push picture handle
        MOVE.L  (SP),-(SP)                      | dup handle for LoadResource
        _LoadResource                           | ensure picture data is in memory
        PEA.L   -0x28(A6)                       | push item display rect
        _DrawPicture                            | draw picture scaled to display rect
DLGMGR_SKIP_2:
        RTS                                     | return from picture drawing

| ----------------------------------------------------------
| Draw statText or editText item.
| If this is the active editText field, erase and TEUpdate.
| Otherwise, perform ParamText substitution (^0..^3) then TETextBox.
| After drawing, if editText, draw 3-pixel frame around display rect.
| ----------------------------------------------------------
DLGMGR_CONT_22:
        SMI.B   D6                              | D6 = $FF if editText (bit 4 set), 0 if statText
        CMP     editField(A4),D3                | is this the active edit field?
        BNE.B   DLGMGR_NO_3                     | no: draw with ParamText substitution
        PEA.L   -0x28(A6)                       | push display rect
        MOVE.L  (SP),-(SP)                      | dup for EraseRect
        _EraseRect                              | clear the edit field area
        MOVE.L  0xA0(A4),-(SP)                  | push TEHandle (teHandle field)
        _TEUpdate                               | redraw active TextEdit content
DLGMGR_CONT_23:
        TST.B   D6                              | was this an editText item?
        BNE.B   DLGMGR_SKIP_3                   | no (statText): skip frame drawing
        LEA.L   -0x28(A6),A0                    | point to item display rect
        MOVEQ.L #0x1,D0                         | pen width = 1 (for non-default editText frame)
        MOVEQ.L #0x1,D1                         | pen height = 1
        MOVEQ.L #0x3,D2                         | inset = 3 pixels outside
        BSR     ENTRY_4                         | draw frame rect around editText item
DLGMGR_SKIP_3:
        RTS                                     | return from editText frame drawing

| ----------------------------------------------------------
| Draw statText/editText with ParamText (^0..^3) substitution.
| Makes a copy of the text handle, scans for '^' markers,
| substitutes from DAStrings[0..3], then draws via TETextBox.
| ----------------------------------------------------------
DLGMGR_NO_3:
        MOVEM.L D2-D6/A2-A4,-(SP)               | save regs (we reuse A2-A4, D2-D6)
        MOVE.L  (A2),A0                         | get text handle
        _HandToHand                             | make working copy (A0 = new handle)
        MOVE.L  A0,A2                           | A2 = working text handle
        MOVEQ.L #0x0,D3                         | D3 = scan offset into text
DLGMGR_EMPTY_2:
        MOVE.L  A2,A0                           | get handle for size check
        _GetHandleSize                          | D0 = total text length
        MOVE.L  (A0),A4                         | A4 = dereferenced text pointer
        ADDA.L  D3,A4                           | advance to current scan position
        MOVE.L  D0,D5                           | D5 = remaining bytes to scan
        SUB.L   D3,D5                           | subtract current offset for remaining bytes
        BRA.B   DLGMGR_LOOP_2                   | enter scan loop

| ----------------------------------------------------------
| Scan for '^' (0x5E) character - ParamText substitution marker.
| Text format: ^0, ^1, ^2, ^3 replaced by DAStrings[0..3].
| ----------------------------------------------------------
DLGMGR_LOOP:
        CMPI.B  #0x5E,(A4)+                     | is this char '^'?
        BEQ.B   DLGMGR_FOUND_2                  | found: go substitute
DLGMGR_SKIP_4:
        ADDQ.W  #0x1,D3                         | advance scan offset
DLGMGR_LOOP_2:
        DBF     D5,DLGMGR_LOOP                  | continue scanning
        BSET    #0x7,(A2)                       | lock the text handle before drawing
        MOVE.L  (A2),-(SP)                      | push text pointer
        MOVE.L  A2,A0                           | A0 = substituted text handle
        _GetHandleSize                          | get length of substituted text
        MOVE.L  D0,-(SP)                        | push text length
        PEA.L   -0x28(A6)                       | push display rect
        CLR     -(SP)                           | justification = teJustLeft (0)
        _TETextBox                              | draw substituted text in rect
        MOVE.L  A2,A0                           | A0 = working text handle to dispose
        _DisposeHandle                          | free working copy
        MOVEM.L (SP)+,D2-D6/A2-A4               | restore regs
        BRA.B   DLGMGR_CONT_23                  | go draw editText frame if needed

| ----------------------------------------------------------
| Found '^' marker - look up which DAStrings[] entry to substitute.
| DAStrings (at DABeeper+4) holds 4 handles for ^0..^3 replacement text.
| D6 scans ASCII '0'..'3' (0x30..0x33) to match char after '^'.
| ----------------------------------------------------------
DLGMGR_FOUND_2:
        LEA.L   (DABeeper).w,A3                 | A3 = base of DABeeper (before DAStrings)
        MOVE.B  #0x2F,D6                        | D6 = '0'-1; will increment to '0' first
DLGMGR_NEXT:
        ADDQ.L  #0x4,A3                         | advance to next DAStrings[] entry
        ADDQ.W  #0x1,D6                         | D6 = next digit char ('0','1','2','3')
        CMPI.B  #0x34,D6                        | past '3'? (checked all 4 substitutions)
        BEQ.B   DLGMGR_SKIP_4                   | no match: skip this '^', continue scan
        CMP.B   (A4),D6                         | does digit match char after '^'?
        BNE.B   DLGMGR_NEXT                     | no: try next DAStrings entry
        MOVEQ.L #0x0,D0                         | D0 = replacement string length (0 if nil)
        MOVE.L  (A3),D4                         | D4 = DAStrings[n] handle
        BEQ.B   DLGMGR_EMPTY_3                  | nil handle: replace with empty string
        MOVE.L  D4,A0                           | A0 = replacement string handle
        BSET    #0x7,(A0)                       | lock the replacement string handle
        MOVE.L  (A0),A0                         | dereference to get string pointer
        MOVE.B  (A0)+,D0                        | D0 = Pascal string length byte
DLGMGR_EMPTY_3:
        SUBQ.W  #0x4,SP                         | space for Munger result
        MOVE.L  A2,-(SP)                        | push target handle (working text copy)
        MOVE.L  D3,-(SP)                        | push offset of '^' in text
        CLR.L   -(SP)                           | push nil for search ptr (delete mode)
        MOVE.L  #0x2,-(SP)                      | push 2 bytes to replace ('^' + digit)
        MOVE.L  A0,-(SP)                        | push replacement string pointer
        MOVE.L  D0,-(SP)                        | push replacement string length
        _Munger                                 | replace "^n" with DAStrings[n] text
        MOVE.L  (SP)+,D0                        | D0 = new match offset from Munger
        TST.L   D4                              | was DAStrings handle non-nil?
        BEQ.B   DLGMGR_EMPTY_2                  | nil: no unlock needed, rescan
        MOVE.L  D4,A0                           | A0 = replacement string handle to unlock
        _HUnlock                                | unlock the replacement string handle
        BRA.B   DLGMGR_EMPTY_2                  | rescan from current position

| ----------------------------------------------------------
| Dispose item resources (D4=2).
| Frees handles for text/icon/picture items, disposes controls.
| Item type dispatch: userItem=RTS, ctrlItem=DisposeControl,
| statText/editText=DisposeHandle, iconItem/picItem=DisposeHandle.
| ----------------------------------------------------------
DLGMGR_CONT_24:
        ROR     #0x3,D0                         | shift ctrlItem bit into carry
        BCS     DLGMGR_SKIP_2                   | ctrlItem: skip (disposed via DisposeControl)
        ROXR    #0x2,D0                         | shift statText/editText bits
        BCS.B   DLGMGR_CONT_26                  | statText: dispose text handle
        BMI.B   DLGMGR_CONT_26                  | editText: dispose text handle
DLGMGR_CONT_25:
        CLR.L   (A2)                            | clear item handle after disposal
        RTS                                     | return from statText/editText disposal

| ----------------------------------------------------------
| Dispose text or icon/picture handle
| ----------------------------------------------------------
DLGMGR_CONT_26:
        _DisposeHandle                          | free the text/icon/picture handle
        BRA.B   DLGMGR_CONT_25                  | clear item handle field

| ----------------------------------------------------------
| DLGMGR_CONT_27 - Dispose a control item (called from CloseDialog's item loop)
| ----------------------------------------------------------
DLGMGR_CONT_27:
        MOVE.L  A0,-(SP)                        | push control handle
        _DisposeControl                         | free control and its data
        BRA.B   DLGMGR_CONT_25                  | clear item handle field

| ----------------------------------------------------------
| Handle activate/deactivate event for dialog's TextEdit field.
| Switches port to target dialog, activates/deactivates its TE,
| then restores original port. Event modifiers bit 0 = activeFlag.
| ----------------------------------------------------------
DLGMGR_CONT_28:
        MOVE.L  -0x4A(A6),A0                    | get event message (dialog window ptr)
        TST     0xA4(A0)                        | check editField: -1 = no edit field
        BMI.B   DLGMGR_EXIT                     | no edit field: nothing to activate
        MOVE.L  0xA0(A0),-(SP)                  | push teHandle for TE call
        MOVE.L  A0,-(SP)                        | push dialog as port
        _SetPort                                | switch to dialog's grafPort
        BTST    #0x0,-0x3D(A6)                  | test activeFlag in event modifiers
        BEQ.B   DLGMGR_NO_4                     | not active: deactivate TE
        _TEActivate                             | show insertion point / selection
        BRA.B   DLGMGR_SKIP_5                   | skip deactivation

| ----------------------------------------------------------
DLGMGR_NO_4:
        _TEDeactivate                           | hide insertion point / selection
DLGMGR_SKIP_5:
        MOVE.L  A4,-(SP)                        | restore original port
        _SetPort                                | restore original grafPort
        BRA.B   DLGMGR_EXIT                     | return itemHit = -1

| ----------------------------------------------------------
| RETURNS_15 - Main dialog event dispatcher
| Called from DialogSelect to process one event in a dialog.
| Dispatches on event.what from -0x4C(A6):
| 1=mouseDown, 3=keyDown, 5=keyDown(autoKey), 6=updateEvt,
| 8=activateEvt, else=nullEvent (TEIdle for caret blink).
| Returns: D3 = item number hit (0-based), or -1 if no item.
| ----------------------------------------------------------
RETURNS_15:
        MOVE    -0x4C(A6),D0                    | get event.what
        SUBQ.W  #0x1,D0                         | test for mouseDown (1)
        BEQ     DLGMGR_CONT_32                  | mouseDown (1): handle click
        SUBQ.W  #0x2,D0                         | test for keyDown (3)
        BEQ.B   DLGMGR_CONT_30                  | keyDown (3): handle keystroke
        SUBQ.W  #0x2,D0                         | test for autoKey (5)
        BEQ.B   DLGMGR_CONT_30                  | autoKey (5): handle repeated key
        SUBQ.W  #0x1,D0                         | test for updateEvt (6)
        BEQ.B   DLGMGR_CONT_29                  | updateEvt (6): redraw dialog
        SUBQ.W  #0x2,D0                         | test for activateEvt (8)
        BEQ.B   DLGMGR_CONT_28                  | activateEvt (8): activate/deactivate TE
        TST     editField(A4)                   | nullEvent: blink caret if edit field active
        BMI.B   DLGMGR_EXIT                     | no edit field: return -1
        MOVE.L  0xA0(A4),-(SP)                  | push teHandle
        _TEIdle                                 | blink insertion point caret
DLGMGR_EXIT:
        MOVEQ.L #-0x1,D3                        | return itemHit = -1 (no item)
        RTS                                     | return to DialogSelect caller

| ----------------------------------------------------------
| Handle updateEvt: redraw entire dialog within update region
| ----------------------------------------------------------
DLGMGR_CONT_29:
        MOVE.L  A4,-(SP)                        | push DialogPtr for EndUpdate
        MOVE.L  (SP),-(SP)                      | dup for DrawDialog
        MOVE.L  (SP),-(SP)                      | dup for BeginUpdate
        _BeginUpDate                            | clip to update region
        _DrawDialog                             | redraw all items
        _EndUpDate                              | restore clipping
        BRA.B   DLGMGR_EXIT                     | return itemHit = -1

| ----------------------------------------------------------
| Handle keyDown/autoKey: dispatch to TEKey or Tab-to-next-field.
| event.message low byte at -0x47(A6) = character code.
| ----------------------------------------------------------
DLGMGR_CONT_30:
        MOVE.B  -0x47(A6),D1                    | get typed character from event.message
        CMPI.B  #0x9,D1                         | Tab key?
        BEQ.B   DLGMGR_NEXT_2                   | yes: advance to next editText field
        MOVE    editField(A4),D3                | get active edit field index
        BMI.B   DLGMGR_EXIT                     | no edit field: ignore keystroke
        MOVE    D1,-(SP)                        | push character for TEKey
        MOVE.L  0xA0(A4),-(SP)                  | push teHandle
        _TEKey                                  | insert typed character into TE
        BRA.B   DLGMGR_EXIT_2                   | return current edit field as itemHit

| ----------------------------------------------------------
| Tab key: find next editText item in DITL and switch to it.
| Wraps around from last editText to first editText.
| ----------------------------------------------------------
DLGMGR_NEXT_2:
        CLR     D5                              | D5 = wrap flag (0=first pass, -1=wrapped)
        MOVE    editField(A4),D3                | start from current edit field
        BSR     DLGMGR_OK_3                     | position to current item in DITL
DLGMGR_SKIP_6:
        BSR     DLGMGR_NEXT_4                   | advance to next DITL item
        BEQ.B   DLGMGR_CONT_31                  | past end of list: try wrapping
        CMP     editField(A4),D3                | back to where we started?
        BEQ.B   DLGMGR_EXIT                     | yes: only one editText, no switch
        BTST    #0x4,0xC(A2)                    | test editText bit in item type
        BEQ.B   DLGMGR_SKIP_6                   | not editText: keep scanning
        BSR     DLGMGR_OK_2                     | check if item rect is on screen
        BEQ.B   DLGMGR_SKIP_6                   | off screen (hidden item): skip it
        MOVE.L  #0x7FFF,D2                      | select all text in new field
        BSR     ENTRY_2                         | switch to this edit field
DLGMGR_EXIT_2:
        BRA.B   DLGMGR_EXIT_4                   | return new edit field as itemHit

| ----------------------------------------------------------
| Reached end of DITL during Tab scan - wrap to beginning.
| Only wraps once (D5 tracks whether we already wrapped).
| ----------------------------------------------------------
DLGMGR_CONT_31:
        TST     D5                              | already wrapped once?
        BMI.B   DLGMGR_EXIT                     | yes: no editText found, give up
        MOVEQ.L #-0x1,D5                        | set wrap flag
        MOVEQ.L #-0x1,D3                        | reset to before first item
        TST     editField(A4)                   | is there any edit field at all?
        BPL.B   DLGMGR_SKIP_6                   | yes: scan from start of DITL
DLGMGR_EXIT_3:
        BRA.B   DLGMGR_EXIT                     | no edit fields at all: return -1

| ----------------------------------------------------------
| Handle mouseDown: convert click to local coords, find which
| DITL item was clicked, then dispatch by item type.
| ----------------------------------------------------------
DLGMGR_CONT_32:
        MOVE.L  -0x42(A6),-0x1C(A6)             | copy event.where to local point
        PEA.L   -0x1C(A6)                       | push ptr to local point
        _GlobalToLocal                          | convert click point to dialog coords
        MOVEQ.L #-0x1,D3                        | start before first item
DLGMGR_NEXT_3:
        BSR     DLGMGR_NEXT_4                   | advance to next DITL item
        BEQ.B   DLGMGR_EXIT_3                   | past end: no item hit, return -1
        SUBQ.W  #0x2,SP                         | space for PtInRect result
        MOVE.L  -0x1C(A6),-(SP)                 | push click point
        PEA.L   -0x28(A6)                       | push item display rect
        _PtInRect                               | is click inside this item?
        TST.B   (SP)+                           | did click intersect item rect?
        BEQ.B   DLGMGR_NEXT_3                   | not in this item: try next
        BTST    #0x2,0xC(A2)                    | is this a ctrlItem?
        BEQ.B   DLGMGR_NO_5                     | no: check for editText click
        SUBQ.W  #0x2,SP                         | space for FindControl result
        MOVE.L  -0x1C(A6),-(SP)                 | push click point
        MOVE.L  A4,-(SP)                        | push dialog window
        PEA.L   -0x18(A6)                       | push ptr for control handle result
        _FindControl                            | find which control was clicked
        MOVE    (SP)+,D0                        | D0 = part code (0=none)
        BEQ.B   DLGMGR_EXIT_3                   | not in a control: return -1
        SUBQ.W  #0x2,SP                         | space for TrackControl result
        MOVE.L  -0x18(A6),-(SP)                 | push control handle
        MOVE.L  -0x1C(A6),-(SP)                 | push click point
        MOVE.L  (MinusOne).w,-(SP)              | push nil actionProc (-1 = default)
        _TrackControl                           | track mouse until released
        TST     (SP)+                           | was control actually clicked?
        BEQ.B   DLGMGR_EXIT_3                   | no: mouse released outside, return -1
DLGMGR_EXIT_4:
        BRA.B   DLGMGR_EXIT_5                   | control was clicked: return item

| ----------------------------------------------------------
| Click was in a non-control item: check if editText.
| If editText, switch edit field and pass click to TEClick.
| ----------------------------------------------------------
DLGMGR_NO_5:
        BTst    #0x4,0xC(A2)                    | test editText bit in item type
        BEQ.B   DLGMGR_EXIT_5                   | not editText: return this item as hit
        CMP     editField(A4),D3                | clicking in already-active field?
        BEQ.B   DLGMGR_OK                       | yes: just pass to TEClick
        MOVEQ.L #0x0,D2                         | D2=0: place insertion point, don't select
        BSR.B   ENTRY_2                         | switch to clicked edit field
DLGMGR_OK:
        TST     editField(A4)                   | is there an active edit field now?
        BMI.B   DLGMGR_EXIT_5                   | no: skip TEClick
        MOVE.L  -0x1C(A6),-(SP)                 | push click point
        BTST    #0x1,-0x3E(A6)                  | test shiftKey in event modifiers
        SNE.B   -(SP)                           | push extend flag (true if Shift held)
        MOVE.L  0xA0(A4),-(SP)                  | push teHandle
        _TEClick                                | handle text selection/insertion
DLGMGR_EXIT_5:
        BTst    #0x7,0xC(A2)                    | test itemDisable bit
        BNE     DLGMGR_EXIT_3                   | disabled item: return -1 (ignore click)
        ADDQ.W  #0x1,D3                         | convert 0-based to 1-based item number
        RTS                                     | return D3 = item number hit

| ----------------------------------------------------------
| ENTRY_2 - Switch active edit field.
| Deactivates current TE (scrolling it back to origin), calls DLGMGR_CONT_33
| to install new field's text into TE, then activates TE.
| Entry: D3 = new field index (0-based), D2 = selection range.
| ----------------------------------------------------------
| Called by: SelIText, GETMAXDEVICE_NO, GETCTSEED_CONT, DLGMGR_SKIP_6, DLGMGR_NO_5
ENTRY_2:
        TST     editField(A4)                   | is there a current edit field?
        BMI.B   DLGMGR_SKIP_7                   | no current field: skip deactivation
        MOVE.L  0xA0(A4),A0                     | get teHandle
        MOVE.L  (A0),A0                         | dereference to TERec
        MOVE.L  0x8(A0),-(SP)                   | push teViewRect.topLeft
        MOVE.L  (A0),-(SP)                      | push teDestRect.topLeft
        PEA.L   0x4(SP)                         | push ptr to delta point on stack
        _SubPt                                  | delta = viewRect.topLeft - destRect.topLeft
        MOVE.L  0xA0(A4),-(SP)                  | push teHandle
        _TEScroll                               | scroll TE back to origin before switching
        MOVE.L  0xA0(A4),-(SP)                  | push teHandle
        _TEDeactivate                           | hide caret/selection in old field
DLGMGR_SKIP_7:
        BSR.B   DLGMGR_CONT_33                  | install new field's text into shared TERec
        TST     editField(A4)                   | did DLGMGR_CONT_33 set a valid edit field?
        BMI.B   DLGMGR_SKIP_8                   | -1 = no edit field: skip activation
        MOVE.L  0xA0(A4),-(SP)                  | push teHandle
        _TEActivate                             | show caret/selection in new field
DLGMGR_SKIP_8:
        RTS                                     | return from edit field setup

| ----------------------------------------------------------
| ENTRY_3 - Check if edit field changed, then install new field.
| Entry: D3 = target field index, D2 = selection range.
| Falls through to DLGMGR_CONT_33 if field is different.
| ----------------------------------------------------------
ENTRY_3:
        CMP     editField(A4),D3                | is target same as current field?
        BEQ.B   DLGMGR_EXIT_6                   | yes: no switch needed, return
| DLGMGR_CONT_33 -- install new field's text into shared TERec.
DLGMGR_CONT_33:
        MOVE.L  (A2),D0                         | D0 = item handle (text handle for editText)
        BLE.B   DLGMGR_EXIT_6                   | nil or negative: no valid text, return
        MOVE    D3,editField(A4)                | set new active edit field index
        BMI.B   DLGMGR_EXIT_6                   | -1 = no field: just clear and return
        MOVE.L  0xA0(A4),A0                     | A0 = teHandle from DialogRecord
        MOVE.L  (A0),A1                         | A1 = dereferenced TERec pointer
        MOVE.L  D0,0x3E(A1)                     | store text handle in TERec.hText (+$3E)
        MOVEQ.L #-0x2,D0                        | sentinel value: don't change selection
        CMP.L   D0,D2                           | D2 = -2 means keep existing selection
        BEQ.B   DLGMGR_SKIP_9                   | skip selection update
        MOVE.L  D2,0x20(A1)                     | set TERec.selStart/selEnd (+$20, packed)
DLGMGR_SKIP_9:
        LEA.L   (A1),A0                         | A0 = TERec base for destRect/viewRect
        MOVE.L  -0x28(A6),(A0)+                 | copy item rect top-left to destRect.topLeft
        MOVE.L  -0x24(A6),(A0)+                 | copy item rect bot-right to destRect.botRight
        MOVE.L  -0x28(A6),(A0)+                 | copy item rect top-left to viewRect.topLeft
        MOVE.L  -0x24(A6),(A0)+                 | copy item rect bot-right to viewRect.botRight
        ST.B    0x32(A1)                        | set TERec.crOnly ($32) = true (word wrap)
        LEA.L   (A1),A0                         | A0 = TERec.destRect.top again
        MOVEQ.L #0x2,D0                         | D0 = 2 (initial line height offset)
        ADD     (A0)+,D0                        | D0 += destRect.top; A0 -> destRect.left
        ADD     0x18(A1),D0                     | D0 += TERec.lineHeight (+$18)
        MOVE    (A0)+,D1                        | D1 = destRect.left; A0 -> destRect.bottom
        CMP     (A0)+,D0                        | compare top+lineHeight+2 vs destRect.bottom
        BLT.B   DLGMGR_SKIP_10                  | fits in one line: skip bottom clamp
        SUB     (A0),D1                         | D1 -= viewRect.left (compute width offset)
        SUB     D1,(A0)                         | adjust viewRect.left to match dest width
DLGMGR_SKIP_10:
        ST.B    -(SP)                           | push TRUE for TEAutoView enable
        MOVE.L  0xA0(A4),-(SP)                  | push teHandle
        _TEAutoView                             | enable auto-scrolling for this TE
        MOVE.L  0xA0(A4),-(SP)                  | push teHandle
        _TECalText                              | recalculate line starts for new text
DLGMGR_EXIT_6:
        RTS                                     | return from edit field activation

| ----------------------------------------------------------
| DLGMGR_OK_2 - Test if item display rect is within dialog's portRect.
| Returns Z=1 if no intersection (item not visible).
| Uses inset=0 (exact rect bounds).
| ----------------------------------------------------------
DLGMGR_OK_2:
        MOVEQ.L #0x0,D0                         | inset = 0 (no expansion)
        BRA.B   DLGMGR_CONT_35                  | share common rect intersection test

| ----------------------------------------------------------
| DLGMGR_CONT_34 - Test if item rect (expanded by 4 pixels) intersects portRect.
| Used during drawing to skip off-screen items.
| Returns Z=1 if no intersection.
| ----------------------------------------------------------
DLGMGR_CONT_34:
        MOVE.L  #0xFFFCFFFC,D0                  | inset = (-4,-4) to include item frame
DLGMGR_CONT_35:
        MOVE.L  0x8(A2),-(SP)                   | push item rect bottom-right
        MOVE.L  0x4(A2),-(SP)                   | push item rect top-left
        MOVE.L  A7,-(SP)                        | push ptr to temp rect on stack
        MOVE.L  D0,-(SP)                        | push inset amount (dh, dv packed)
        _InsetRect                              | shrink rect by negative inset (expand it)
        CLR     -(SP)                           | space for SectRect boolean result
        PEA.L   0x2(SP)                         | push ptr to temp rect
        PEA.L   0x10(A4)                        | push dialog portRect (+$10 in GrafPort)
        PEA.L   0xA(SP)                         | push ptr to dummy dest rect on stack
        _SectRect                               | test intersection of item rect and portRect
        MOVE.B  (SP)+,D0                        | D0 = TRUE if rects intersect
        ADDQ.W  #0x8,SP                         | clean up temp rect from stack
        RTS                                     | return visibility boolean in D0

| ----------------------------------------------------------
| ENTRY_4 - Draw a rounded-rect frame around an item rect.
| Entry: A0 = ptr to rect, D0 = pen width, D1 = pen height,
| D2 = outward inset (positive = expand outward).
| Expands rect outward by D2, frames it, then restores rect.
| ----------------------------------------------------------
ENTRY_4:
        MOVE.L  A0,-(SP)                        | push rect ptr for 2nd InsetRect (restore)
        MOVE    D2,-(SP)                        | push +D2 horizontal (shrink back later)
        MOVE    D2,-(SP)                        | push +D2 vertical
        MOVE.L  A0,-(SP)                        | push rect ptr for FrameRoundRect
        MOVE    D1,-(SP)                        | push oval height for rounded corners
        MOVE    D1,-(SP)                        | push oval width for rounded corners
        MOVE.L  A0,-(SP)                        | push rect ptr for 1st InsetRect (expand)
        NEG     D2                              | negate: now -D2 = expand outward
        MOVE    D2,-(SP)                        | push -D2 horizontal inset (expand)
        MOVE    D2,-(SP)                        | push -D2 vertical inset (expand)
        MOVE    D0,-(SP)                        | push pen width for PenSize
        MOVE    D0,-(SP)                        | push pen height for PenSize
        _PenSize                                | set pen to D0 x D0 pixels
        _InsetRect                              | expand rect outward by D2 pixels
        _FrameRoundRect                         | draw rounded-rect frame
        _InsetRect                              | restore rect to original size
        RTS                                     | return from rounded-rect frame drawing

| ----------------------------------------------------------
| ENTRY_5 - Create a new string handle from a Pascal string.
| Entry: A0 = ptr to Pascal string.
| Exit: A0 = new string handle. Preserves D1-D2, A1-A2.
| Note: saves D0-D2/A1-A2 but restores D1-D2/A1-A2 only
| (D0 is clobbered by NewString result, shifts registers).
| ----------------------------------------------------------
ENTRY_5:
        MOVEM.L D0-D2/A1-A2,-(SP)               | save regs (5 longs = 20 bytes)
        MOVE.L  A0,-(SP)                        | push string ptr for NewString
        _NewString                              | create handle with copy of string
        MOVE.L  (SP)+,A0                        | A0 = new string handle
        MOVEM.L (SP)+,D1-D2/A1-A2               | restore D1-D2/A1-A2 (skip saved D0)
        RTS                                     | return with new string handle in A0

| ----------------------------------------------------------
| DLGMGR_NEXT_4 - Advance to the next DITL item.
| Increments D3 (item index), then positions A2 at next item.
| If D3 was -1 (no current item), falls into DLGMGR_OK_3 to start
| from the beginning. Returns Z=1 if past end of item list.
| ----------------------------------------------------------
| Called by: CLOSEDIALOG_NO_2, SETITEXT_NEXT_2, FINDDITEM_NEXT, FINDDITEM_EXIT_2, DLGMGR_SKIP_6 (and 1 more)
DLGMGR_NEXT_4:
        ADDQ.W  #0x1,D3                         | advance to next item index
        BEQ.B   DLGMGR_OK_3                     | was -1: start from first item
        MOVE.L  D2,-(SP)                        | save D2 (used as byte accumulator)
        MOVEQ.L #0x1,D0                         | skip 1 item (advance from current)
        BRA.B   DLGMGR_SKIP_11                  | enter item-skip loop

| ----------------------------------------------------------
| DLGMGR_OK_3 - Position A2 at DITL item number D3.
| Walks the variable-length DITL item list from the beginning,
| skipping D3 items to reach the target. D7 accumulates byte
| offset. Returns A2 = ptr to item, Z=1 if past end.
| ----------------------------------------------------------
| Called by: INITDIALOGS_OK, CLOSEDIALOG_CONT_5, GetDItem, SetDItem, SelIText (and 3 more)
DLGMGR_OK_3:
        MOVE.L  D2,-(SP)                        | save D2 (used as byte accumulator)
        MOVEQ.L #0x0,D7                         | D7 = running byte offset into DITL data
        MOVE    D3,D0                           | D0 = number of items to skip
        BLT.B   DLGMGR_EXIT_7                   | negative index: return nil
DLGMGR_SKIP_11:
        MOVEQ.L #0x0,D2                         | clear D2 for byte-size data length reads
        MOVE.L  A3,D1                           | test items handle (A3)
        BEQ.B   DLGMGR_EXIT_7                   | nil handle: return nil
        MOVE.L  (A3),A2                         | dereference items handle to DITL data
        MOVE    (A2)+,D1                        | D1 = item count - 1 (DITL stores count-1)
        CMP     D3,D1                           | is target index within range?
        BGE.B   DLGMGR_OK_4                     | yes: start walking items
DLGMGR_EXIT_7:
        SUBA.L  A2,A2                           | A2 = nil (past end of list)
        BRA.B   DLGMGR_EXIT_8                   | return with Z=1

| ----------------------------------------------------------
| DLGMGR_LOOP_3 - Skip one DITL item entry (variable-length).
| Each item: 4-byte handle + 8-byte rect + 1-byte type +
| 1-byte data length + data (padded to even boundary).
| ----------------------------------------------------------
DLGMGR_LOOP_3:
        MOVE.B  0xD(A2,D7.W),D2                 | D2 = data length byte at item+13+offset
        ADD     D2,D7                           | advance offset by data length
        ADDI    #0xF,D7                         | add 15 (14 fixed bytes + round up)
        ANDI    #-0x2,D7                        | align to even byte boundary
DLGMGR_OK_4:
        DBF     D0,DLGMGR_LOOP_3                | skip D0 items
        ADDA    D7,A2                           | A2 = ptr to target item entry
        BSR.B   DLGMGR_CONT_36                  | copy item's display rect to -0x28(A6)
DLGMGR_EXIT_8:
        MOVE.L  (SP)+,D2                        | restore D2
        MOVE.L  A2,D0                           | set Z flag: Z=1 if A2 is nil (past end)
        RTS                                     | return with Z flag set if past end

| ----------------------------------------------------------
| DLGMGR_CONT_36 - Copy item's display rect to local frame variable.
| Copies 8 bytes from item+4 (display rect) to -0x28(A6).
| ----------------------------------------------------------
DLGMGR_CONT_36:
        LEA.L   0x4(A2),A0                      | A0 = ptr to item's display rect
        LEA.L   -0x28(A6),A1                    | A1 = ptr to local rect variable
        MOVE.L  (A0)+,(A1)+                     | copy rect top-left (top, left)
        MOVE.L  (A0)+,(A1)+                     | copy rect bottom-right (bottom, right)
        RTS                                     | return from rect copy

