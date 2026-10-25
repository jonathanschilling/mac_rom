| -----------------------------------------------------------
|
|
|     ****   *****   ***   ***   ***   *   *   ***
|     *   *  *      *   *   *   *   *  *   *  *   *
|     *   *  *      *       *   *   *  **  *  *
|     ****   ***    *  **   *   *   *  * * *   ***
|     * *    *      *   *   *   *   *  *  **      *
|     *  *   *      *   *   *   *   *  *   *  *   *
|     *   *  *****   ***   ***   ***   *   *   ***
|
|
|
|  QuickDraw Routines to operate on Regions.

StdRgn:
        LINK    A6,#0x0                         | set up stack frame (no locals)
        MOVEM.L D6-D7/A2-A4,-(SP)               | SAVE REGS
        MOVE.B  12(A6),D7                       | GET VERB
        JSR     CheckPic(PC)                    | SET UP A4,A3 AND CHECK PICSAVE
        BLE.W   STDRGN_NOTPIC                   | BRANCH IF NOT PICSAVE
        MOVE.B  D7,-(SP)                        | PUSH VERB
        JSR     PutPicVerb(PC)                  | PUT ADDIONAL PARAMS TO THEPIC
        MOVE    #0x80,D0                        | rgnNoun in hi nibble (0x80)
        ADD     D7,D0                           | PUT VERB IN LO NIBBLE
        MOVE.B  D0,-(SP)                        | push opcode byte
        JSR     PutPicByte(PC)                  | PUT OPCODE TO THEPIC
        MOVE.L  8(A6),-(SP)                     | PUSH RGNHANDLE
        JSR     PutPicRgn(PC)                   | PUT REGION TO THEPIC
STDRGN_NOTPIC:
        MOVE.L  8(A6),-(SP)                     | PUSH RGNHANDLE
        JSR     PushVerb(PC)                    | PUSH MODE AND PATTERN
        TST.B   D7                              | IS VERB FRAME ?
        BNE.B   STDRGN_NOTPIC_NO_2              | NO, CONTINUE
        TST.L   0x60(A3)                        | YES, IS RGNSAVE TRUE ?
        BEQ.B   STDRGN_NOTPIC_NO                | NO, CONTINUE
        MOVE.L  8(A6),-(SP)                     | YES, PUSH RGNHANDLE
        MOVE.L  -0x94(A4),-(SP)                 | PUSH RGNBUF
        PEA.L     -0x96(A4)                     | PUSH VAR RGNINDEX
        PEA.L     -0x98(A4)                     | PUSH VAR RGNMAX
        JSR     PutRgn(PC)                      | ADD INVERSION PTS TO THERGN
STDRGN_NOTPIC_NO:
        JSR     FrRgn(PC)                       | FrRgn(rgn,pnMode,pnPat)
        BRA.B   STDRGN_NOTPIC_CONT              | skip non-frame DrawRgn
STDRGN_NOTPIC_NO_2:
        JSR     DrawRgn(PC)                     | DrawRgn(rgn,mode,pat);
STDRGN_NOTPIC_CONT:
        MOVEM.L (SP)+,D6-D7/A2-A4               | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        ADDQ.W  #0x6,SP                         | strip 6 bytes of params
        JMP     (A0)                            | RTS
| Called by: FrameRgn, PaintRgn, EraseRgn, InverRgn, FillRgn
CallRgn:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP RGN
        MOVE.B  D0,-(SP)                        | PUSH VERB
        MOVE.L  A1,-(SP)                        | PUSH RGN
        MOVE.L  A0,-(SP)                        | RESTORE RETURN ADDR
        MOVE.L  (A5),A0                         | A0 := QD globals
        MOVE.L  (A0),A0                         | A0 := thePort
        MOVE.L  0x68(A0),D0                     | D0 := grafProcs
        LEA     StdRgn(PC),A0                   | default proc = StdRgn
        BEQ.B   CALLRGN_USESTD                  | YES, USE STD PROC
        MOVE.L  D0,A0                           | A0 := grafProcs ptr
        MOVE.L  28(A0),A0                       | NO, GET PROC PTR
CALLRGN_USESTD:
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| PROCEDURE FrameRgn(rgn: RgnHandle).
FrameRgn:
        MOVEQ.L #0x0,D0                         | VERB = FRAME
        JMP     CallRgn(PC)                     | SHARE COMMON CODE

| PROCEDURE PaintRgn(rgn: RgnHandle).
PaintRgn:
        MOVEQ.L #0x1,D0                         | VERB = PAINT
        JMP     CallRgn(PC)                     | SHARE COMMON CODE

| PROCEDURE EraseRgn(rgn: RgnHandle).
EraseRgn:
        MOVEQ.L #0x2,D0                         | VERB = ERASE
        JMP     CallRgn(PC)                     | SHARE COMMON CODE

| ----------------------------------------------------------
| _InverRgn ($A8D5): invert the pixels inside a region
| Pascal: PROCEDURE InvertRgn(rgn: RgnHandle);
| CallRgn with verb invert (3): calls the port's rgnProc (StdRgn if
| grafProcs is nil).
| Apple source name: InvertRgn (1983 Regions.a; MacSEROM.lst: INVERTRGN)
InverRgn:
        MOVEQ.L #0x3,D0                         | VERB = INVERT
        JMP     CallRgn(PC)                     | SHARE COMMON CODE

| PROCEDURE FillRgn(rgn: RgnHandle; pat: Pattern).
FillRgn:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF PATTERN
        MOVE.L  A0,-(SP)                        | RESTORE RETURN ADDR
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        LEA.L     0x28(A0),A0                   | POINT TO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | COPY PAT INTO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | ALL EIGHT BYTES
        MOVEQ.L #0x4,D0                         | VERB = FILL
        JMP     CallRgn(PC)                     | SHARE COMMON CODE

| .PROC DrawRgn,3
| .REF RgnBlt
| --------------------------------------------------------
| PROCEDURE DrawRgn(rgn: RgnHandle; mode: INTEGER; pat: Pattern);
| A6 OFFSETS OF PARAMS AFTER LINK:
| PARAMSIZE .EQU 10
| RGN .EQU PARAMSIZE+8-4 ;LONG, RGNHANDLE
| MODE .EQU RGN-2 ;WORD
| PAT .EQU MODE-4 ;LONG, ADDR OF PATTERN
| Called during boot.
DrawRgn:
        LINK    A6,#0x0                         | ESTABLISH STACK FRAME
        MOVE.L  (A5),A0                         | POINT TO GRAFGLOBALS
        MOVE.L  (A0),A0                         | POINT TO THEPORT
        TST     0x42(A0)                        | IS PNVIS NEG ?
        BMI.B   DRAWRGN_EXIT_2                  | YES, QUIT
        PEA.L     2(A0)                         | PUSH SRCBITS
        MOVE.L  (SP),-(SP)                      | PUSH DSTBITS
        PEA.L     8(A0)                         | PUSH PORTBITS+BOUNDS (SRCRECT)
        MOVE.L  (SP),-(SP)                      | PUSH DSTRECT
        MOVE    12(A6),-(SP)                    | PUSH MODE
        MOVE.L  8(A6),-(SP)                     | PUSH PAT
        MOVE.L  28(A0),-(SP)                    | PUSH CLIPRGN
        MOVE.L  24(A0),-(SP)                    | PUSH VISRGN
        MOVE.L  14(A6),-(SP)                    | PUSH RGN
        JSR     RgnBlt(PC)                      | CALL RGNBLT
DRAWRGN_EXIT_2:                                 | jump via A0
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDA.W  #0xA,SP                         | strip 10 bytes of params
        JMP     (A0)                            | RTS

| .PROC FrRgn,3
| .REF FrRect,NewRgn,CopyRgn,InsetRgn,DiffRgn,DrawRgn
| --------------------------------------------------------
| PROCEDURE FrRgn(rgn: RgnHandle; mode: INTEGER; pat: Pattern);
| A6 OFFSETS OF PARAMS AFTER LINK:
| PARAMSIZE .EQU 10
| RGN .EQU PARAMSIZE+8-4 ;LONG, RGNHANDLE
| MODE .EQU RGN-2 ;WORD
| PAT .EQU MODE-4 ;LONG, ADDR OF PATTERN
| Called during boot.
FrRgn:
        LINK    A6,#0x0                         | set up stack frame (no locals)
        MOVEM.L D7/A3-A4,-(SP)                  | SAVE REGS
        MOVE.L  (A5),A4                         | A4 := QD globals
        MOVE.L  (A4),A3                         | A3 := thePort
        TST     0x42(A3)                        | is pnVis < 0?
        BMI.W   FRRGN_CONT                      | YES, QUIT
        MOVE.L  14(A6),A0                       | GET RGNHANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        CMPI    #0xA,(A0)                       | is rgn rectangular (size==10)?
        BNE.B   FRRGN_NOTRECT                   | NO, CONTINUE
        PEA.L     2(A0)                         | YES, PUSH ADDR OF BBOX
        JSR     FrRect(PC)                      | jump via A0
        BRA.B   FRRGN_CONT                      | AND QUIT
FRRGN_NOTRECT:
        CLR.L   -(SP)                           | NOTRECT: MAKE ROOM FOR FCN RESULT
        JSR     NewRgn(PC)                      | ALLOCATE TEMPRGN
        MOVE.L  (SP)+,D7                        | PUT TEMPRGN IN D7
        MOVE.L  14(A6),-(SP)                    | PUSH RGN
        MOVE.L  D7,-(SP)                        | PUSH TEMPRGN
        JSR     CopyRgn(PC)                     | COPY RGN INTO TEMPRGN
        MOVE.L  D7,-(SP)                        | PUSH TEMPRGN
        MOVE.L  0x34(A3),-(SP)                  | PUSH PNSIZE
        JSR     InsetRgn(PC)                    | InsetRgn(tempRgn,pnSize);
        MOVE.L  14(A6),-(SP)                    | PUSH RGN
        MOVE.L  D7,-(SP)                        | PUSH TEMPRGN
        MOVE.L  D7,-(SP)                        | PUSH TEMPRGN
        JSR     DiffRgn(PC)                     | DiffRgn(rgn,tempRgn,tempRgn);
        MOVE.L  D7,-(SP)                        | PUSH TEMPRGN
        MOVE    12(A6),-(SP)                    | PUSH MODE
        MOVE.L  8(A6),-(SP)                     | PUSH PAT
        JSR     DrawRgn(PC)                     | DrawRgn(tempRgn,mode,pat);
        MOVE.L  D7,-(SP)                        | push tempRgn for dispose
        JSR     DisposRgn(PC)                   | DisposeRgn(tempRgn)
FRRGN_CONT:
        MOVEM.L (SP)+,D7/A3-A4                  | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDA.W  #0xA,SP                         | strip 10 bytes of params
        JMP     (A0)                            | RTS

| .FUNC NewRgn,0
| .REF NewHandle
| ---------------------------------------------------
| FUNCTION NewRgn;
| Allocate a new region and set it to the empty region.
| Called during boot (4,158 times in 30s trace).
NewRgn:
        MOVEM.L D3/A2,-(SP)                     | SAVE REGS
        CLR.L   -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE    #0xA,-(SP)                      | PUSH BYTECOUNT=10
        JSR     NewHandle_Inline(PC)            | ALLOCATE A RELOCATABLE OBJECT
        MOVE.L  (SP)+,A0                        | POP RESULTING HANDLE
        MOVEM.L (SP)+,D3/A2                     | RESTORE REGS
        MOVE.L  A0,4(SP)                        | STORE INTO NEWRGN RESULT
        MOVE.L  (A0),A0                         | DE-REFERENCE HANDLE
        MOVE    #0xA,(A0)+                      | INSTALL RGNSIZE=10
        CLR.L   (A0)+                           | INSTALL RGNBBOX=(0,0,0,0)
        CLR.L   (A0)+                           | CLEAR RGNBBOX BOTTOM,RIGHT
        RTS                                     | return from NewRgn
| ----------------------------------------------------------
|
| _DisposRgn ($A8D9): dispose of a region
| Pascal: PROCEDURE DisposeRgn(rgn: RgnHandle);
| Pops the return address (A0) and rgn (A1), saves D3, A2 and the return
| address, and calls KILLPICTURE_BODY with rgn (pop handle, _DisposHandle).
| Net effect: _DisposHandle(rgn), preserving D3/A2. KillPoly jumps here.
| (The 1983 Regions.a DisposeRgn is an inline pop/_DisposHandle/return.)
| Apple source name: DisposeRgn (1983 Regions.a; MacSEROM.lst: DISPOSERGN)
| Called by: ClosePort, NOTPORT_NO, MORE, EMPTY, DrawPoly (and 2 more)
DisposRgn:
        MOVE.L  (SP)+,A0                        | A0 = return address
        MOVE.L  (SP)+,A1                        | A1 = rgn handle
        MOVEM.L D3/A0/A2,-(SP)                  | save D3, return addr, A2
        MOVE.L  A1,-(SP)                        | push rgn as the parameter
        JSR     KILLPICTURE_BODY(PC)            | _DisposHandle(rgn)
        MOVEM.L (SP)+,D3/A0/A2                  | restore D3, A0 = return addr, A2
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| PROCEDURE OpenRgn;
| rgnSave := TRUE, rgnIndex := 0, allocate a 256-byte rgnBuf for the
| inversion points (rgnMax := 256), HidePen.
OpenRgn:
        MOVEM.L D3/A2-A4,-(SP)                  | SAVE REGS
        MOVE.L  (A5),A4                         | A4 := QD globals
        MOVE.L  (A4),A0                         | A0 := thePort
        MOVE.L  #0x1,0x60(A0)                   | rgnSave := TRUE
        CLR     -0x96(A4)                       | rgnIndex := 0
        CLR.L   -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE    #0x100,-(SP)                    | push byteCount = 256
        MOVE    (SP),-0x98(A4)                  | rgnMax := 256
        JSR     NewHandle_Inline(PC)            | allocate rgnBuf (256 bytes)
        MOVE.L  (SP)+,-0x94(A4)                 | rgnBuf := new handle
        JSR     HidePen(PC)                     | suppress drawing while building
        MOVEM.L (SP)+,D3/A2-A4                  | RESTORE REGS
        RTS                                     | AND RETURN

| .PROC CloseRgn,1
| .REF ShowPen,SortPoints,CullPoints,PackRgn
| ---------------------------------------------------
| PROCEDURE CloseRgn(* dstRgn: RgnHandle *);
| Sort array of inversion points and pack into region.
| A6 OFFSETS OF PARAMS AND LOCALS AFTER LINK:
| PARAMSIZE .EQU 4 ;TOTAL BYTES OF PARAMETERS
| DSTRGN .EQU PARAMSIZE+8-4 ;LONG, RGNHANDLE
| PTCOUNT .EQU -2 ;WORD
| VARSIZE .EQU PTCOUNT ;SIZE OF LOCAL VARS
| Called during boot.
CloseRgn:
        LINK    A6,#-0x2                        | ESTABLISH STACK FRAME
        MOVEM.L D3/A2-A4,-(SP)                  | SAVE REGS
        MOVE.L  (A5),A4                         | POINT TO GRAFGLOBALS
        MOVE.L  (A4),A0                         | POINT TO THEPORT
        TST.L   0x60(A0)                        | IS RGNSAVE TRUE ?
        BEQ.B   CLOSERGN_EXIT                   | NO, NOTHING TO CLOSE
        CLR.L   0x60(A0)                        | YES, RGNSAVE := FALSE
        JSR     ShowPen(PC)                     | UNDO THE HIDEPEN FROM OPENRGN
        MOVE    -0x96(A4),D0                    | GET CURRENT RGNINDEX
        LSR     #0x2,D0                         | DIV BY 4
        MOVE    D0,-2(A6)                       | FOR PTCOUNT
        MOVE.L  -0x94(A4),A3                    | GET RGNBUF HANDLE
        MOVE.L  (A3),-(SP)                      | PUSH BUF POINTER
        MOVE    D0,-(SP)                        | PUSH PTCOUNT
        JSR     SortPoints(PC)                  | QUICKSORT IN VH ORDER
        MOVE.L  (A3),-(SP)                      | PUSH BUF POINTER
        PEA.L     -2(A6)                        | PUSH VAR PTCOUNT
        JSR     CullPoints(PC)                  | CANCEL DUPLICATE PAIRS
        MOVE.L  A3,-(SP)                        | PUSH RGNBUF HANDLE
        MOVE    -2(A6),-(SP)                    | PUSH (UPDATED) PTCOUNT
        MOVE.L  8(A6),-(SP)                     | PUSH DSTRGN
        JSR     PackRgn(PC)                     | PACK POINTS INTO DSTRGN
        MOVE.L  A3,-(SP)                        | push rgnBuf handle
        JSR      KILLPICTURE_BODY(PC)           | DISCARD RGNBUF
CLOSERGN_EXIT:
        MOVEM.L  (SP)+,D3/A2-A4                 | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,(SP)                      | RESTORE RETURN ADDR
        RTS                                     | return from CLOSERGN_EXIT

| .PROC CopyRgn,1
| .REF SetSize
| ---------------------------------------------------
| PROCEDURE CopyRgn(* srcRgn,dstRgn: RgnHandle *);
| PARAMSIZE .EQU 8
| SRCRGN .EQU PARAMSIZE+8-4 ;RGNHANDLE
| DSTRGN .EQU SRCRGN-4 ;RGNHANDLE
| Called during boot (9,298 times in 30s trace).
CopyRgn:
        LINK    A6,#0x0                         | ESTABLISH STACK FRAME
        MOVE.L  12(A6),A0                       | GET SRCRGN HANDLE
        MOVE.L  8(A6),A1                        | GET DSTRGN HANDLE
        CMPA.L  A0,A1                           | same handle (no-op copy)?
        BEQ.B   COPYRGN_EXIT                    | YES, QUIT
        MOVE.L  (A0),A0                         | DE-REFERENCE SRCRGN HANDLE
        MOVE.L  (A1),A1                         | DE-REFERENCE DSTRGN HANDLE
        MOVE    (A0),D0                         | GET SRCRGN SIZE
        CMP     (A1),D0                         | IS DSTRGN SIZE SAME AS SRCRGN SIZE?
        BEQ.B   COPYRGN_OK                      | YES, CONTINUE
        MOVEM.L D0/D3/A2,-(SP)                  | SAVE REGS AND BYTECOUNT
        MOVE.L  8(A6),-(SP)                     | PUSH DSTRGN HANDLE
        MOVE    D0,-(SP)                        | PUSH NEWSIZE=SRC SIZE
        JSR     SetHSize(PC)                    | CHANGE SIZE OF DST
        MOVEM.L (SP)+,D0/D3/A2                  | RESTORE REGS AND BYTECOUNT
        MOVE.L  12(A6),A0                       | GET SRCRGN HANDLE
        MOVE.L  8(A6),A1                        | GET DSTRGN HANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE SRCRGN HANDLE
        MOVE.L  (A1),A1                         | DE-REFERENCE DSTRGN HANDLE
COPYRGN_OK:
        LSR     #0x2,D0                         | LONGCOUNT := BYTECOUNT DIV 4
        BCC.B   COPYRGN_OK_2                    | WAS THERE AN ODD WORD ?
        MOVE    (A0)+,(A1)+                     | YES, DO IT TO MAKE EVEN
        BRA.B   COPYRGN_OK_2                    | AND CONTINUE
COPYRGN_LOOP:
        MOVE.L  (A0)+,(A1)+                     | PUSH RIGHT,BOTTOM
COPYRGN_OK_2:
        DBRA    D0,COPYRGN_LOOP                 | LOOP FOR ALL LONGS
COPYRGN_EXIT:
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDQ.W  #0x8,SP                         | strip 8 bytes of params
        JMP     (A0)                            | RTS

| .PROC SetEmptyRgn,1
| .REF SetRectRgn
| ---------------------------------------------------
| PROCEDURE SetEmptyRgn(rgn: RgnHandle);
| Called during boot.
SetEmptyRgn:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        CLR.L   -(SP)                           | PUSH LEFT, TOP
        CLR.L   -(SP)                           | PUSH RIGHT,BOTTOM
        MOVE.L  A0,-(SP)                        | RESTORE RETURN ADDR
        JMP     SetRecRgn(PC)                   | DOUBLE UP ON CODE
| ----------------------------------------------------------
|
| _SetRecRgn ($A8DE): make a rectangular region from four coordinates
| Pascal: PROCEDURE SetRectRgn(rgn: RgnHandle; left, top, right, bottom: INTEGER);
| Resizes rgn to 10 bytes if needed and sets rgnBBox; an empty rectangle
| gives the empty region (0,0,0,0). SetEmptyRgn and RectRgn jump here.
| Apple source name: SetRectRgn (1983 Regions.a; MacSEROM.lst: SETRECTRGN)
|
SetRecRgn:
        LINK    A6,#0x0                         | set up stack frame (no locals)
        MOVEM.L D3/A2,-(SP)                     | SAVE REGS
        MOVE.L  16(A6),A0                       | GET RGN HANDLE
        MOVE.L  (A0),A1                         | DE-REFERENCE HANDLE
        CMPI    #0xA,(A1)                       | IS RGNSIZE ALREADY 10 ?
        BEQ.B   SETRECTRGN_OK                   | YES, CONTINUE
        MOVE.L  A0,-(SP)                        | PUSH RGNHANDLE
        MOVE    #0xA,-(SP)                      | push newSize = 10 (rect rgn)
        JSR     SetHSize(PC)                    | CHANGE SIZE OF REGION
        MOVE.L  16(A6),A0                       | GET RGN HANDLE
        MOVE.L  (A0),A1                         | DE-REFERENCE HANDLE
        MOVE    #0xA,(A1)                       | install rgnSize := 10
SETRECTRGN_OK:
        MOVE.L  12(A6),2(A1)                    | SET RGNBBOX TOPLEFT
        MOVE.L  8(A6),6(A1)                     | SET RGNBBOX BOTRIGHT
        MOVE    4(A1),D0                        | GET LEFT
        CMP     8(A1),D0                        | IS LEFT >= RIGHT ?
        BGE.B   SETRECTRGN_EMPTY                | YES, SET TO EMPTY
        MOVE    2(A1),D0                        | GET TOP
        CMP     6(A1),D0                        | IS TOP < BOTTOM ?
        BLT.B   SETRECTRGN_DONE                 | YES, CONTINUE
SETRECTRGN_EMPTY:
        CLR.L   2(A1)                           | rgnBBox topLeft := (0,0)
        CLR.L   6(A1)                           | rgnBBox botRight := (0,0)
SETRECTRGN_DONE:
        MOVEM.L (SP)+,D3/A2                     | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDA.W  #0xC,SP                         | strip 12 bytes of params
        JMP     (A0)                            | RTS
RectRgn:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF RECT
        MOVE.L  (A1)+,-(SP)                     | PUSH LEFT,TOP
        MOVE.L  (A1)+,-(SP)                     | PUSH RIGHT,BOTTOM
        MOVE.L  A0,-(SP)                        | RESTORE RETURN ADDR
        JMP     SetRecRgn(PC)                   | DOUBLE UP ON CODE

| .PROC OffsetRgn
| ----------------------------------------------------------
|
| _OfSetRgn ($A8E0): move a region by (dh, dv)
| Pascal: PROCEDURE OffsetRgn(rgn: RgnHandle; dh, dv: INTEGER);
| Offsets rgnBBox and, for a non-rectangular region, every vertical and
| horizontal coordinate of the region data (up to the $7FFF terminators).
| Apple source name: OffsetRgn (1983 Regions.a; MacSEROM.lst: OFFSETRGN)
| Called during boot.
|
OfsetRgn:
        MOVE.L  (SP)+,A1                        | POP RETURN ADDR
        MOVE    (SP)+,D1                        | POP DV
        MOVE    (SP)+,D0                        | POP DH
        MOVE.L  (SP)+,A0                        | POP RGN HANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        ADDQ.W  #0x2,A0                         | POINT TO RGNBBOX
        ADD     D1,(A0)+                        | ADD DV TO TOP
        ADD     D0,(A0)+                        | ADD DH TO LEFT
        ADD     D1,(A0)+                        | ADD DV TO BOTTOM
        ADD     D0,(A0)+                        | ADD DH TO RIGHT
        CMPI    #0xA,-10(A0)                    | IS REGION RECTANGULAR?
        BEQ.B   OFFSETRGN_NXTHOR_DONE           | IF SO, WE'RE ALL DONE
OFFSETRGN_LOOP:
        ADD.W    D1,(A0)+                       | offset vert coord by dv
OFFSETRGN_NXTHOR:
        ADD     D0,(A0)+                        | NXTHOR: OFFSET LEFT COORD DH
        ADD     D0,(A0)+                        | OFFSET RIGHT COORD DH
        CMPI    #0x7FFF,(A0)                    | IS HORIZ END MARKER?
        BNE.B   OFFSETRGN_NXTHOR                | NO, LOOP
        ADDQ.W  #0x2,A0                         | SKIP OVER HORIZ TERMINATOR
        CMPI    #0x7FFF,(A0)                    | IS NEXT VERT = 32767 (END OF RGN) ?
        BNE.B   OFFSETRGN_LOOP                  | NO, LOOP FOR MORE
OFFSETRGN_NXTHOR_DONE:
        JMP     (A1)                            | RETURN
InsetRgn:
        LINK    A6,#0x0                         | set up stack frame (no locals)
        MOVEM.L D3-D7/A2-A4,-(SP)               | SAVE REGS
        MOVE.L  8(A6),D6                        | D6 := dv:dh as long
        BEQ.W   SWAP2_CONT                      | QUIT IF BOTH ARE ZERO
        MOVE.L  12(A6),A4                       | GET RGNHANDLE
        MOVE.L  (A4),A3                         | DE-REFERENCE IT
        MOVE    (A3)+,D7                        | GET RGNSIZE
        CMPI    #0xA,D7                         | is rgn rectangular?
        BNE.B   INSETRGN_NOTRECT                | NO, CONTINUE
        MOVE.L  A3,-(SP)                        | PUSH ADDR OF RGNBBOX
        MOVE.L  D6,-(SP)                        | PUSH DH AND DV
        JSR     InsetRect(PC)                   | InsetRect(rgn^^.rgnbbox,dh,dv);
        MOVE    2(A3),D0                        | GET BBOX LEFT
        CMP     6(A3),D0                        | IS LEFT >= RIGHT ?
        BGE.B   INSETRGN_EMPTY                  | YES, RETURN EMPTY RGN
        MOVE    (A3),D0                         | get bbox.top
        CMP     4(A3),D0                        | IS TOP >= BOTTOM ?
        BLT.W   SWAP2_CONT                      | NO, CONTINUE
INSETRGN_EMPTY:
        CLR.L   (A3)+                           | SET RGNBBOX TO (0,0,0,0) TO
        CLR.L   (A3)+                           | RETURN EMPTY REGION
        BRA.W   SWAP2_CONT                      | jump via A0
INSETRGN_NOTRECT:
        ADD     D7,D7                           | NOTRECT: TRY BYTES NEEDED = RGNSIZE*2
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        MOVE    D7,-(SP)                        | PUSH BYTESNEEDED
        JSR     NewHandle_Inline(PC)            | ALLOCATE PTBUF
        MOVE.L  (SP)+,A3                        | PUT PTBUF HANDLE IN A3
        BSR.B   HINSET                          | INSET HORIZ AND FLIP
        SWAP    D6                              | GET DV INSTEAD OF DH
        BSR.B   HINSET                          | INSET VERTICAL AND FLIP BACK
        BRA.W   INSETRGN_FINISH                 | tail-merge with shared finish code

| --------------------------------------------------------------------------
| LOCAL ROUTINE TO INSET HORIZONTALLY, SWAP H AND V COORDS, AND RE-SORT
| RgnOp(rgn,rgn,bufHandle,maxBytes,op,dh,TRUE);
HINSET:
        CLR     -(SP)                           | ROOM FOR FCN RESULT
        MOVE.L  A4,-(SP)                        | PUSH RGNA = USER RGN
        MOVE.L  A4,-(SP)                        | PUSG RGNB = USER RGN ALSO
        MOVE.L  A3,-(SP)                        | PUSH BUFHANDLE
        MOVE    D7,-(SP)                        | PUSH MAXBYTES
        MOVE    #0x8,-(SP)                      | PUSH OP = INSET
        MOVE    D6,-(SP)                        | PUSH DH
        ST      -(SP)                           | PUSH OKGROW = TRUE
        JSR     RgnOp(PC)                       | PERFORM REGION OPERATION
        MOVE    (SP)+,D5                        | POP PTCOUNT RESULT
        MOVE.L  (A3),A0                         | DE-REFERENCE PTBUF HANDLE
        MOVE    D5,D1                           | COPY PTCOUNT
        BRA.B   SWAP2                           | GO TO LOOP START

| ----------------------------------------------------------
| SWAPLP
SWAPLP:
        MOVE.L  (A0),D0                         | GET A POINT
        SWAP    D0                              | SWAP ITS COORDINATES
        MOVE.L  D0,(A0)+                        | PUT IT BACK INTO ARRAY
SWAP2:
        DBRA    D1,SWAPLP                       | LOOP FOR ALL POINTS
        MOVE.L  (A3),-(SP)                      | PUSH PTBUF PTR
        MOVE    D5,-(SP)                        | PUSH PTCOUNT
        JSR     SortPoints(PC)                  | RE-SORT INTO VH ORDER
        MOVE.L  A3,-(SP)                        | PUSH PTBUF HANDLE
        MOVE    D5,-(SP)                        | PUSH PTCOUNT
        MOVE.L  A4,-(SP)                        | PUSH RGN HANDLE
        JSR     PackRgn(PC)                     | PackRgn(ptBuf,ptCount,rgn);
        RTS                                     | RETURN TO LOCAL CALLER

INSETRGN_FINISH:                                | InsetRgn shared tail
        MOVE.L  A3,-(SP)                        | push ptBuf handle for dispose
        JSR     KILLPICTURE_BODY(PC)            | dispose ptBuf handle
SWAP2_CONT:
        MOVEM.L (SP)+,D3-D7/A2-A4               | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDQ.W  #0x8,SP                         | strip 8 bytes of params
        JMP     (A0)                            | RTS
| ----------------------------------------------------------
|
| _EmptyRgn ($A8E2): test whether a region is empty
| Pascal: FUNCTION EmptyRgn(rgn: RgnHandle): BOOLEAN;
| Replaces the parameter by @rgn^^.rgnBBox and jumps to EmptyRect.
|
EmptyRgn:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP RGNHANDLE
        MOVE.L  (A1),A1                         | DE-REFERENCE HANDLE
        PEA.L     2(A1)                         | PUSH RGNBBOX
        MOVE.L  A0,-(SP)                        | PUSH RETURN ADDR
        JMP     EmptyRect(PC)                   | USE EMPTYRECT CODE

| .FUNC EqualRgn,2
| -------------------------------------------------------
| FUNCTION EqualRgn(rgnA,rgnB: RgnHandle): BOOLEAN;
| RETURNS TRUE IF RGNA AND RGNB DESCRIBE THE SAME AREA
| Called during boot (10,214 times in 30s trace).
EqualRgn:
        MOVE.L  4(SP),A0                        | GET RGNA HANDLE
        MOVE.L  8(SP),A1                        | GET RGNB HANDLE
        CMPA.L  A0,A1                           | same handle (trivially equal)?
        BEQ.B   EQUALRGN_LOOP2_OK               | YES, THE REGIONS ARE THE SAME
        MOVE.L  (A0),A0                         | DE-REFERENCE RGN A
        MOVE.L  (A1),A1                         | DE-REFERENCE RGN B
        MOVE    (A0),D0                         | GET RGNSIZE A
        MOVE    D0,D1                           | MAKE AN EXTRA COPY
        LSR     #0x2,D1                         | DIV BY 4 FOR LONG COUNT
        SUBQ.W  #0x1,D1                         | ADJUST FOR DBF
EQUALRGN_LOOP:
        CMPM.L  (A0)+,(A1)+                     | COMPARE A LONG
        DBNE    D1,EQUALRGN_LOOP                | LOOK TILL DIFFERENT OR COUNT
        BNE.B   EQUALRGN_LOOP2_CONT             | DIFFERENT --> FALSE
        ANDI    #0x3,D0                         | GET REMAINING BYTES
        BEQ.B   EQUALRGN_LOOP2_OK               | IF NO MORE, WE MADE IT
EQUALRGN_LOOP2:
        CMPM.B  (A0)+,(A1)+                     | COMPARE A BYTE
        BNE.B   EQUALRGN_LOOP2_CONT             | BR IF DIFFERENT
        SUBQ.W  #0x1,D0                         | decrement byte counter
        BNE.B   EQUALRGN_LOOP2                  | LOOP LAST 1..3 BYTES
EQUALRGN_LOOP2_OK:
        MOVE.B  #0x1,12(SP)                     | return TRUE in fcn result
        BRA.B   EQUALRGN_DONE                   | skip false branch
EQUALRGN_LOOP2_CONT:
        CLR.B   12(SP)                          | return FALSE in fcn result
EQUALRGN_DONE:
        MOVE.L  (SP)+,A0                        | PUSH DSTRGN
        ADDQ.W  #0x8,SP                         | strip 8 bytes of params
        JMP     (A0)                            | RTS
| ----------------------------------------------------------
| PROCEDURE SectRgn(srcRgnA, srcRgnB, dstRgn: RgnHandle);
SectRgn:
        MOVEQ.L #0x0,D0                         | op = 0 (intersect)
        JMP     DoRgnOp(PC)                     | dispatch to common
| PROCEDURE UnionRgn(srcRgnA, srcRgnB, dstRgn: RgnHandle);
UnionRgn:
        MOVEQ.L #0x4,D0                         | op = 4 (union)
        JMP     DoRgnOp(PC)                     | dispatch to common
| PROCEDURE DiffRgn(srcRgnA, srcRgnB, dstRgn: RgnHandle);
DiffRgn:
        MOVEQ.L #0x2,D0                         | op = 2 (A - B)
        JMP     DoRgnOp(PC)                     | dispatch to common
| PROCEDURE XorRgn(srcRgnA, srcRgnB, dstRgn: RgnHandle);
XorRgn:
        MOVEQ.L #0x6,D0                         | op = 6 (xor)
        JMP     DoRgnOp(PC)                     | dispatch to common

| ---------------------------------------------------------
| PROCEDURE DoRgnOp(srcRgnA,srcRgnB,dstRgn: RgnHandle);
| Computes the Intersection, Difference, Union, or Xor of two regions.
| enter with op in D0.
| op = 0: SectScan
| 2: DIFF A-B
| 4: UNION
| 6: XOR
| A6 OFFSETS OF PARAMS AND LOCALS AFTER LINK:
| PARAMSIZE .EQU 12
| RGNA .EQU PARAMSIZE+8-4 ;LONG, RGNHANDLE
| RGNB .EQU RGNA-4 ;LONG, RGNHANDLE
| DSTRGN .EQU RGNB-4 ;LONG, RGNHANDLE
| TEMPRECT .EQU -8 ;RECT
| VARSIZE .EQU TEMPRECT ;TOTAL LOCALS
| Called during boot (10,214 times in 30s trace).
DoRgnOp:
        LINK    A6,#-0x8                        | link frame, 8 bytes locals (TEMPRECT)
        MOVEM.L D3-D7/A2-A4,-(SP)               | SAVE REGS
        MOVE    D0,D5                           | GET LEFT
        MOVE.L  16(A6),A2                       | GET RGNA
        MOVE.L  12(A6),A3                       | GET RGNB
        MOVE.L  8(A6),A4                        | GET RGNA LEFT
        CLR.B   -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE.L  A2,-(SP)                        | PUSH RGNA
        MOVE.L  A3,-(SP)                        | YES, GET RGNB INSTEAD
        JSR     EqualRgn(PC)                    | CALL EQUALRGN
        TST.B   (SP)+                           | ARE THEY THE SAME ?
        BEQ.B   XORRGN_NOTSAME                  | NO, CONTINUE
        ANDI    #0x2,D5                         | test bit 1 of op (XOR/UNION = 0)
        BNE.B   XORRGN_ZERO                     | NO, ZERO OUT DSTRGN
XORRGN_COPY:
        MOVE.L  A2,-(SP)                        | PUSH RGNA
        MOVE.L  A4,-(SP)                        | PUSH DSTRGN
        JSR     CopyRgn(PC)                     | COPY RGNA INTO DSTRGN
        BRA.W   JDONE_DONE                      | AND QUIT
XORRGN_ZERO:
        MOVE.L  A4,-(SP)                        | PUSH DSTRGN
        JSR     SetEmptyRgn(PC)                 | SET IT TO EMPTY
        BRA.W   JDONE_DONE                      | AND QUIT
XORRGN_NOTSAME:
        MOVE.L  (A2),A0                         | DE-REFERENCE RGNA
        MOVE.L  (A3),A1                         | DE-REFERENCE RGNB
        CMPI    #0x2,D5                         | is op > 2 (UNION/XOR)?
        BGT.B   UNIXOR                          | NO, ITS UNION OR XOR
        BLT.B   BBOXES                          | NO, IT'S SECT
        MOVE    4(A1),D0                        | op == DIFF: get rgnB.left
        CMP     8(A1),D0                        | rgnB empty (left >= right)?
        BGE.B   XORRGN_COPY                     | YES, COPY RGNA INTO DST
| IF op = SectScan OR DIFF, THEN INTERSECT THE BOUNDING BOXES.
| Called during boot (10,188 times in 30s trace).
BBOXES:
        PEA.L     2(A0)                         | PUSH RGNA^^.RGNBBOX
        PEA.L     2(A1)                         | PUSH RGNB^^.RGNBBOX
        MOVE    #0x2,-(SP)                      | PUSH NRECTS = 2
        PEA.L     -8(A6)                        | PUSH DST = TEMPRECT
        JSR     RSect(PC)                       | CALC INTERSECTION
        BNE.B   BBOXES_EMPTY                    | BR IF RESULT NOT EMPTY
        TST     D5                              | IS OP = SectScan ?
        BEQ.B   XORRGN_ZERO                     | YES, RETURN EMPTY
        BRA.B   XORRGN_COPY                     | NO, COPY SRCA INTO DSTRGN
BBOXES_EMPTY:                                   | jump via A0
        MOVE.L  (A2),A0                         | DE-REFERENCE RGNA
        MOVE.L  (A3),A1                         | DE-REFERENCE RGNB
        TST     D5                              | IS OP = SECT ?
        BNE.B   JDONE_NO_2                      | NO, CONTINUE
        CMPI    #0xA,(A0)                       | is rgnA rectangular?
        BNE.B   JDONE_NO_2                      | NO, CONTINUE
        CMPI    #0xA,(A1)                       | is rgnB rectangular?
        BNE.B   JDONE_NO_2                      | NO, CONTINUE
        MOVE.L  A4,-(SP)                        | PUSH DSTRGN
        PEA.L     -8(A6)                        | push addr of TEMPRECT
        JSR     RectRgn(PC)                     | RectRgn(dstRgn,tempRect);
        BRA.W   JDONE_DONE                      | done with two-rect Sect
UNIXOR:
        MOVE    4(A1),D0                        | GET LEFT
        CMP     8(A1),D0                        | COMPARE TO RIGHT
        BGE.B   XORRGN_COPY                     | YES, COPY RGNA INTO DST
        MOVE    4(A0),D0                        | GET RGNA LEFT
        CMP     8(A0),D0                        | COMPARE TO RGNA RIGHT
        BLT.B   JDONE_NO_2                      | NO, CONTINUE
        MOVE.L  A3,A2                           | YES, GET RGNB INSTEAD
        BRA.W   XORRGN_COPY                     | COPY RGNB INTO DST

| ----------------------------------------------------------
| JDONE_NO_2
| Called during boot (7,414 times in 30s trace).
JDONE_NO_2:
        MOVE    (A0),D4                         | GET RGNA SIZE
        ADD     (A1),D4                         | ADD RGNB SIZE
        ADD     D4,D4                           | TRY DOUBLE FOR BYTECOUNT
        CLR.L   -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE    D4,-(SP)                        | PUSH BYTECOUNT
        JSR     NewHandle_Inline(PC)            | ALLOCATE PTBUF
        MOVE.L  (SP)+,A3                        | GET PTBUF HANDLE IN A3
        CLR     -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE.L  16(A6),-(SP)                    | PUSH RGNA
        MOVE.L  12(A6),-(SP)                    | PUSH RGNB
        MOVE.L  A3,-(SP)                        | PUSH BUFHANDLE
        MOVE    D4,-(SP)                        | PUSH MAXBYTES
        MOVE    D5,-(SP)                        | PUSH OP
        CLR     -(SP)                           | PUSH DH=0
        ST      -(SP)                           | PUSH OKGROW = TRUE
        JSR     RgnOp(PC)                       | PERFORM REGION OPERATION
        MOVE    (SP)+,D6                        | GET PTCOUNT
        MOVE.L  A3,-(SP)                        | PUSH PTBUF HANDLE
        MOVE    D6,-(SP)                        | PUSH PTCOUNT
        MOVE.L  A4,-(SP)                        | PUSH DSTRGN
        JSR     PackRgn(PC)                     | PackRgn(ptBuf,ptCount,dstRgn);
        MOVE.L  A3,-(SP)                        | push ptBuf handle for dispose
        JSR      KILLPICTURE_BODY(PC)           | DISCARD PTBUF
JDONE_DONE:                                     | jump via A0
        MOVEM.L (SP)+,D3-D7/A2-A4               | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDA.W  #0xC,SP                         | strip 12 bytes of params
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| PtInRgn -- _PtInRgn ($A8E8).
| Tests if a point is inside a region. Uses bbox check first,
| then walks the inversion-point list for non-rectangular regions.
PtInRgn:
        LINK    A6,#0x0                         | ENTRY: NO LOCAL VARS
        MOVE.L  D3,-(SP)                        | SAVE REG
        MOVE    14(A6),D1                       | GET PT.H
        MOVE    12(A6),D2                       | GET PT.V
        CLR     D3                              | INIT INSIDE:=FALSE
        MOVE.L  8(A6),A0                        | GET RGN HANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        CMP     4(A0),D1                        | IS PT.H < BBOX LEFT?
        BLT.B   NEXTHOR_EXIT                    | YES, RETURN FALSE
        CMP     8(A0),D1                        | IS PT.H >= BBOX RIGHT?
        BGE.B   NEXTHOR_EXIT                    | YES, RETURN FALSE
        CMP     2(A0),D2                        | IS PT.V < BBOX TOP?
        BLT.B   NEXTHOR_EXIT                    | YES, RETURN FALSE
        CMP     6(A0),D2                        | IS PT.V >= BBOX BOTTOM?
        BGE.B   NEXTHOR_EXIT                    | YES, RETURN FALSE
        CMPI    #0xA,(A0)                       | IS REGION RECTANGULAR?
        BNE.B   PTINRGN_NO                      | NO, CONTINUE
        NOT     D3                              | YES, RETURN TRUE
        BRA.B   NEXTHOR_EXIT                    | GO TO DONE
PTINRGN_NO:
        LEA.L     10(A0),A0                     | POINT TO FIRST VERT COORD
PTINRGN_NEXT:
        CMP     (A0)+,D2                        | IS NEXT VERT > PT.V ?
        BLT.B   NEXTHOR_EXIT                    | YES, QUIT
NEXTHOR:
        MOVE    (A0)+,D0                        | GET HORIZ COORD
        CMPI    #0x7FFF,D0                      | IS HORIZ END MARKER?
        BEQ.B   PTINRGN_NEXT                    | YES, GET NEXT VERT COORD
        CMP     D1,D0                           | IS HORIZ <= PT.H ?
        BGT.B   NEXTHOR                         | NO, IGNORE THIS POINT
        NOT     D3                              | YES, TOGGLE INSIDE
        BRA.B   NEXTHOR                         | AND GO FOR MORE POINTS

| ----------------------------------------------------------
| NEXTHOR_EXIT
| Called during boot (4,005 times in 30s trace).
NEXTHOR_EXIT:
        NEG.B   D3                              | DONE: BOOLEAN RESULT IS 0 OR 1
        MOVE.B  D3,0x10(A6)                     | RETURN BOOLEAN FCN RESULT
        MOVE.L  (SP)+,D3                        | RESTORE REG
        UNLK    A6                              | RELEASE STACK FRAME
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDQ.W  #0x8,SP                         | STRIP PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER
| ----------------------------------------------------------
|
| _RectInRgn ($A8E9): test whether a rectangle intersects a region
| Pascal: FUNCTION RectInRgn(r: Rect; rgn: RgnHandle): BOOLEAN;
| minRect := r SECT rgnBBox (RSect); FALSE if empty, TRUE if rgn is
| rectangular. Otherwise plays the region back into a scan buffer on the
| stack (InitRgn/SeekRgn) and returns TRUE if any scan line from
| minRect.top to minRect.bottom is non-zero. As IM I notes, the result
| may be TRUE when r only meets the region's enclosing rectangle.
|
RectInRgn:
        LINK    A6,#-0x24                       | set up stack frame
        MOVEM.L D0-D7/A1-A5,-(SP)               | SAVE REGISTERS
        MOVE.L  SP,-12(A6)                      | SAVESTK := SP for buffer cleanup
        CLR.B   16(A6)                          | INIT BOOLEAN RESULT TO FALSE
        MOVE.L  8(A6),A1                        | GET REGION HANDLE
        MOVE.L  (A1),A1                         | DE-REFERENCE IT
        MOVE.L  12(A6),-(SP)                    | PUSH POINTER TO RECT
        PEA.L     2(A1)                         | PUSH POINTER TO RGN BBOX
        MOVE    #0x2,-(SP)                      | push nRects = 2
        PEA.L     -8(A6)                        | push addr of MINRECT (dst)
        JSR     RSect(PC)                       | CALC INTERSECTION
        BEQ.W   TRUE_EXIT                       | QUIT IF NO INTERSECTION
        CMPI    #0xA,(A1)                       | is rgn rectangular?
        BEQ.W   TRUE                            | YES, RETURN TRUE
        MOVE.L  A1,A0                           | GET RGNPTR IN A0
        LEA.L     -0x24(A6),A1                  | A1 := state record addr
        MOVE    -6(A6),D0                       | D0 := minH (minRect.left)
        MOVE    -2(A6),D1                       | D1 := maxH (minRect.right)
        MOVE    D0,D2                           | BUFLEFT:=MINH
        JSR     InitRgn(PC)                     | INIT RECORD, ALLOCATE BUFFER
        MOVE    20(A1),D5                       | GET BUFSIZE= # LONGS -1
        LSR     #0x5,D5                         | div by 32 bits per long
        MOVE    -8(A6),D0                       | D0 := minRect.top (start vert)
        JSR     SeekRgn(PC)                     | SEEK THE REGION TO MINRECT TOP
        MOVE    -4(A6),D6                       | D6 := minRect.bottom (limit vert)
TESTBUF:
        MOVE.L  8(A1),A0                        | POINT TO SCAN BUFFER START
        MOVE    D5,D0                           | INIT LOOP COUNT TO BUFSIZE
NXTLONG:                                        | test the scan buffer a long at a time
        TST.L   (A0)+                           | IS SCAN BUF NON-ZERO ?
        DBNE    D0,NXTLONG                      | TEST LONGS TILL NON ZERO OR END
        BNE.B   TRUE                            | WE FOUND A NON-ZERO, RETURN TRUE
        MOVE    16(A1),D0                       | GET NEXT VERTICAL IN RGN
        CMP     D0,D6                           | IS NEXT RGN VERT BEYOND BOTTOM ?
        BLE.B   TRUE_EXIT                       | YES, RETURN FALSE
        JSR     SeekRgn(PC)                     | NO, SEEK TO NEXT VERT CHANGE
        BRA.B   TESTBUF                         | AND SEE IF IT IS NON-ZERO
TRUE:
        ADDQ.B  #0x1,16(A6)                     | SET BOOLEAN RESULT TO TRUE
TRUE_EXIT:
        MOVE.L  -12(A6),SP                      | restore SP from SAVESTK (free buf)
        MOVEM.L (SP)+,D0-D7/A1-A5               | RESTORE REGISTERS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDQ.W  #0x8,SP                         | strip 8 bytes of params
        JMP     (A0)                            | RTS
| ----------------------------------------------------------
|
| TrimRect - clip a rectangle to a region if the result is rectangular
| FUNCTION TrimRect(rgn: RgnHandle; VAR dstRect: Rect): BOOLEAN;
| (internal, no trap; DrText calls it to test for its fast case)
| Fakes a rectangular region from dstRect and a 24-byte point buffer on
| the stack (fake master pointers, so no heap allocation) and calls
| RgnOp(rgn, rectRgn, buf, 24, sect, 0, okGrow = FALSE). ptCount = 4:
| dstRect := the intersection, TRUE; ptCount < 4 (empty): dstRect :=
| (0,0,0,0), TRUE; ptCount > 4 (not rectangular): FALSE, dstRect kept.
| (The 1983 Regions.a version returns this tristate in the CCR.)
|
TrimRect:
        LINK    A6,#-0x2A                       | set up stack frame
        MOVEM.L D0-D7/A1-A4,-(SP)               | save D0-D7,A1-A4
        CLR.B   16(A6)                          | boolean fcn result := FALSE
        LEA.L     -24(A6),A0                    | A0 := PTDATA (room for 6 points)
        MOVE.L  A0,-28(A6)                      | PTMASTER := @PTDATA (fake buf master)
        LEA.L     -0x26(A6),A1                  | A1 := REGION (rect rgn data)
        MOVE.L  A1,-0x2A(A6)                    | RGNMASTER := @REGION (fake rgn master)
        MOVE    #0xA,(A1)+                      | rectRgn.size := 10 (rect)
        MOVE.L  8(A6),A0                        | POINT TO DSTRECT
        MOVE.L  (A0)+,(A1)+                     | COPY DSTRECT TOPLEFT
        MOVE.L  (A0)+,(A1)+                     | COPY DSTRECT BOTRIGHT
        CLR     -(SP)                           | room for RgnOp result
        MOVE.L  12(A6),-(SP)                    | PUSH RGN
        PEA.L     -0x2A(A6)                     | PUSH FAKE RGNHANDLE (@RGNMASTER)
        PEA.L     -28(A6)                       | PUSH FAKE BUFHANDLE (@PTMASTER)
        MOVE    #0x18,-(SP)                     | push maxBytes = 24
        CLR.L   -(SP)                           | PUSH OP = SECT, DH = 0
        CLR.B   -(SP)                           | PUSH OKGROW = FALSE
        JSR     RgnOp(PC)                       | RgnOp(rgn,rectRgn,buf,64,op,dh,FALSE);
        MOVE.L  8(A6),A0                        | POINT TO DSTRECT
        CMPI    #0x4,(SP)+                      | COMPARE PT COUNT WITH 4
        BGT.B   TRIMRECT_RETURN                 | > 4: not rectangular, return FALSE
        BLT.B   TRIMRECT_CLR                    | < 4: empty
        MOVE.L  -24(A6),(A0)+                   | copy intersection topLeft to dst
        MOVE.L  -12(A6),(A0)+                   | copy intersection botRight to dst
        BRA.B   TRIMRECT_SET                    | set true result
TRIMRECT_CLR:
        CLR.L   (A0)+                           | dstRect topLeft := (0,0)
        CLR.L   (A0)+                           | dstRect botRight := (0,0)
TRIMRECT_SET:
        ADDQ.B  #0x1,16(A6)                     | RESULT := TRUE
TRIMRECT_RETURN:
        MOVEM.L (SP)+,D0-D7/A1-A4               | restore registers
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR INTO A0
        ADDQ.W  #0x8,SP                         | STRIP PARAMETERS
        JMP     (A0)                            | RTS

| .PROC MapRgn,3
| .REF MapRect,NewHandle,PutRgn,MapPt
| .REF SortPoints,CullPoints,PackRgn
| -------------------------------------------------------------
| PROCEDURE MapRgn(rgn: RgnHandle; fromRect,toRect: Rect);
| A6 OFFSETS OF PARAMETERS AND LOCALS AFTER LINK:
| PARAMSIZE .EQU 12
| RGN .EQU PARAMSIZE+8-4 ;LONG, RGNHANDLE
| FROMRECT .EQU RGN-4 ;LONG, ADDR OF RECT
| TORECT .EQU FROMRECT-4 ;LONG, ADDR OF RECT
MapRgn:
        LINK    A6,#-0x6                        | ESTABLISH STACK FRAME
        MOVEM.L D3/D6-D7/A2-A4,-(SP)            | SAVE REGS
        MOVE.L  12(A6),A0                       | POINT TO FROMRECT
        MOVE.L  8(A6),A1                        | POINT TO TORECT
        CMPM.L  (A0)+,(A1)+                     | IS TOPLEFT SAME ?
        BNE.B   MAPRGN_NO                       | NO, CONTINUE
        CMPM.L  (A0)+,(A1)+                     | YES, IS BOTRIGHT SAME TOO ?
        BEQ.W   PLUS_5_CONT                     | jump via A0
| SPECIAL CASE RECTANGULAR RGN
MAPRGN_NO:
        MOVE.L  16(A6),A4                       | GET RGNHANDLE
        MOVE.L  (A4),A0                         | DE-REFERENCE RGN
        CMPI    #0xA,(A0)                       | IS REGION RECTANGULAR?
        BNE.B   MAPRGN_NO_2                     | NO, CONTINUE
        PEA.L     2(A0)                         | YES, PUSH RGNBBOX
        MOVE.L  12(A6),-(SP)                    | PUSH FROMRECT
        MOVE.L  8(A6),-(SP)                     | PUSH TO RECT
        JSR     MapRect(PC)                     | MapRect(rgn^^.rgnBBox,from,to);
        BRA.B   PLUS_5_CONT                     | rect rgn done, exit
MAPRGN_NO_2:
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        MOVE    #0x100,-(SP)                    | push byteCount = 256
        JSR     NewHandle_Inline(PC)            | ALLOCATE PTBUF
        MOVE.L  (SP)+,A3                        | GET PTBUF HANDLE IN A3
        CLR     -2(A6)                          | local index := 0
        MOVE    #0x100,-4(A6)                   | local size := 256
        MOVE.L  A4,-(SP)                        | PUSH RGN
        MOVE.L  A3,-(SP)                        | PUSH PTBUF HANDLE
        PEA.L     -2(A6)                        | push var index addr
        PEA.L     -4(A6)                        | push var size addr
        JSR     PutRgn(PC)                      | UNPACK RGN INTO INVERSION PTS
        MOVE    -2(A6),D7                       | get final index (bytes used)
        LSR     #0x2,D7                         | ptCount := index / 4
        MOVE    D7,D6                           | COPY PTCOUNT FOR LOOP COUNT
        MOVE.L  (A3),A2                         | DE-REFERENCE PTBUF HANDLE
        BRA.B   MAPRGN_LOOP_2                   | GO TO LOOP START
MAPRGN_LOOP:
        MOVE.L  A2,-(SP)                        | LOOP: PUSH ADDR OF AN INV PT
        MOVE.L  12(A6),-(SP)                    | PUSH FROMRECT
        MOVE.L  8(A6),-(SP)                     | PUSH TORECT
        JSR     MapPt(PC)                       | MAP THIS POINT
        ADDQ.L  #0x4,A2                         | ADVANCE TO NEXT POINT
MAPRGN_LOOP_2:
        DBRA    D6,MAPRGN_LOOP                  | LOOP ALL INVERSION POINTS
        MOVE.L  (A3),-(SP)                      | PUSH PTBUF PTR
        MOVE    D7,-(SP)                        | PUSH PTCOUNT
        JSR     SortPoints(PC)                  | SortPoints(ptBuf^,ptCount)
        MOVE.L  (A3),-(SP)                      | PUSH PTBUF PTR
        MOVE    D7,-6(A6)                       | PUT PTCOUNT IN MEMORY
        PEA.L     -6(A6)                        | PUSH VAR PTCOUNT
        JSR     CullPoints(PC)                  | CullPoints(ptBuf^,ptCount)
        MOVE.L  A3,-(SP)                        | PUSH PTBUF HANDLE
        MOVE    -6(A6),-(SP)                    | PUSH PTCOUNT
        MOVE.L  A4,-(SP)                        | PUSH RGN
        JSR     PackRgn(PC)                     | PackRgn(ptBuf,ptCount,rgn);
        MOVE.L  A3,-(SP)                        | push ptBuf handle for dispose
        JSR     KILLPICTURE_BODY(PC)            | DISCARD PTBUF
PLUS_5_CONT:
        MOVEM.L (SP)+,D3/D6-D7/A2-A4            | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDA.W  #0xC,SP                         | strip 12 bytes of params
        JMP     (A0)                            | RTS

