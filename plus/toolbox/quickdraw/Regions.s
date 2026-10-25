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
|

| .PROC StdRgn,2
| .REF CheckPic,PutPicVerb,DPutPicByte,PutPicRgn
| .REF PutRgn,FrRgn,PushVerb,DrawRgn
| ---------------------------------------------------------------
|
| PROCEDURE StdRgn(verb: GrafVerb; rgn: RgnHandle);
|
| A6 OFFSETS OF PARAMS AFTER LINK:
|
| Called during boot.
StdRgn:
.set PARAMSIZE, 6                               | TOTAL BYTES OF PARAMS
.set VERB, PARAMSIZE+8-2                        | GRAFVERB
.set RGN, VERB-4                                | LONG, RGNHANDLE

        LINK    A6,#0                           | NO LOCALS
        MOVEM.L D6-D7/A2-A4,-(SP)               | SAVE REGS
        MOVE.B  0xC(A6),D7                      | GET VERB
        JSR     CheckPic(PC)                    | SET UP A4,A3 AND CHECK PICSAVE
        BLE.B   STDRGN_NOTPIC                   | BRANCH IF NOT PICSAVE
        MOVE.B  D7,-(SP)                        | PUSH VERB
        JSR     PutPicVerb(PC)                  | PUT ADDIONAL PARAMS TO THEPIC
        MOVE    #0x80,D0                        | PUT RGNNOUN IN HI NIBBLE
        ADD     D7,D0                           | PUT VERB IN LO NIBBLE
        JSR     DPutPicByte(PC)                 | PUT OPCODE TO THEPIC
        MOVE.L  0x8(A6),-(SP)                   | PUSH RGNHANDLE
        JSR     PutPicRgn(PC)                   | PUT REGION TO THEPIC
STDRGN_NOTPIC:
        MOVE.L  0x8(A6),-(SP)                   | PUSH RGNHANDLE
        JSR     PushVerb(PC)                    | PUSH MODE AND PATTERN
        TST.B   D7                              | IS VERB FRAME ?
        BNE.B   STDRGN_NOTFR                    | NO, CONTINUE
        TST.L   RGNSAVE(A3)                     | YES, IS RGNSAVE TRUE ?
        BEQ.B   STDRGN_NOTRGN                   | NO, CONTINUE
        MOVE.L  0x8(A6),-(SP)                   | YES, PUSH RGNHANDLE
        MOVE.L  RGNBUF(A4),-(SP)                | PUSH RGNBUF
        PEA.L   RGNINDEX(A4)                    | PUSH VAR RGNINDEX
        PEA.L   RGNMAX(A4)                      | PUSH VAR RGNMAX
        JSR     PutRgn(PC)                      | ADD INVERSION PTS TO THERGN
STDRGN_NOTRGN:
        JSR     FrRgn(PC)                       | FrRgn(rgn,pnMode,pnPat)
        BRA.B   STDRGN_GOHOME                   | GO TO GOHOME

| ----------------------------------------------------------
|
| STDRGN_NOTFR
|
| Called during boot.
STDRGN_NOTFR:
        JSR     DrawRgn(PC)                     | DrawRgn(rgn,mode,pat);
STDRGN_GOHOME:
        MOVEM.L (SP)+,D6-D7/A2-A4               | GOHOME: RESTORE REGS
        UNLK    A6                              | RELEASE STACK FRAME
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDQ.W  #0x6,SP                         | STRIP PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER

| .PROC FrameRgn,1
| .DEF CallRgn,PaintRgn,EraseRgn,InvertRgn,FillRgn
| .REF StdRgn
| -----------------------------------------------------
|
| PROCEDURE FrameRgn(* rgn: RgnHandle *);
|
| Called during boot.
FrameRgn:
        MOVEQ.L #0x0,D0                         | VERB = FRAME
        BRA.B   CallRgn                         | SHARE COMMON CODE

| -----------------------------------------------------
|
| PROCEDURE PaintRgn(* rgn: RgnHandle *);
|
PaintRgn:
        MOVEQ.L #0x1,D0                         | VERB = PAINT
        BRA.B   CallRgn                         | SHARE COMMON CODE

| --------------------------------------------------------
|
| PROCEDURE EraseRgn(* rgn: RgnHandle *);
|
| Called during boot.
EraseRgn:
        MOVEQ.L #0x2,D0                         | VERB = ERASE
        BRA.B   CallRgn                         | SHARE COMMON CODE

| --------------------------------------------------------
|
| PROCEDURE InvertRgn(* rgn: RgnHandle *);
|
InverRgn:
        MOVEQ.L #0x3,D0                         | VERB = INVERT
        BRA.B   CallRgn                         | SHARE COMMON CODE

| --------------------------------------------------------
|
| PROCEDURE FillRgn(* rgn: RgnHandle; pat: Pattern *);
|
FillRgn:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF PATTERN
        MOVE.L  A0,-(SP)                        | PUT RETURN ADDR BACK
        MOVE.L  (A5),A0                         | POINT TO GRAFGLOBALS
        MOVE.L  (A0),A0                         | POINT TO THEPORT
        LEA.L   FILLPAT(A0),A0                  | POINT TO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | COPY PAT INTO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | ALL EIGHT BYTES
        MOVEQ.L #0x4,D0                         | VERB = FILL
        NOP                                     | SHARE COMMON CODE WITH CALLRGN

| ---------------------------------------------------------------
|
| PROCEDURE CallRgn(rgn: RgnHandle);
|
| code shared by FrameRgn, PaintRgn, EraseRgn, InvertRgn, and FillRgn.
| enter with verb in D0.
|
| Called during boot.
CallRgn:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP RGN
        MOVE.B  D0,-(SP)                        | PUSH VERB
        MOVE.L  A1,-(SP)                        | PUSH RGN
        MOVE.L  A0,-(SP)                        | RESTORE RETURN ADDR
        MOVE.L  (A5),A0                         | POINT TO GRAFGLOBALS
        MOVE.L  (A0),A0                         | POINT TO THEPORT
        MOVE.L  GRAFPROCS(A0),D0                | IS GRAFPROCS NIL ?
        MOVE.L  (0xF44).w,A0                    | _StdRgn (rgnProc)
        BEQ.B   CALLRGN_USESTD                  | YES, USE STD PROC
        MOVE.L  D0,A0                           | PUT PROC PTR IN A0
        MOVE.L  RGNPROC(A0),A0                  | NO, GET PROC PTR
CALLRGN_USESTD:
        JMP     (A0)                            | USESTD: GO TO IT

| .PROC DrawRgn,3
| .REF RgnBlt
| --------------------------------------------------------
|
| PROCEDURE DrawRgn(rgn: RgnHandle; mode: INTEGER; pat: Pattern);
|
| A6 OFFSETS OF PARAMS AFTER LINK:
|
| PARAMSIZE .EQU 10
| RGN .EQU PARAMSIZE+8-4 ;LONG, RGNHANDLE
| MODE .EQU RGN-2 ;WORD
| PAT .EQU MODE-4 ;LONG, ADDR OF PATTERN
| Called during boot.
DrawRgn:
.set PARAMSIZE, 10                              | TOTAL BYTES OF PARAMS
.set RGN, PARAMSIZE+8-4                         | LONG, RGNHANDLE
.set MODE, RGN-2                                | WORD
.set PAT, MODE-4                                | LONG, ADDR OF PATTERN

        LINK    A6,#0                           | ESTABLISH STACK FRAME
        MOVE.L  (A5),A0                         | POINT TO GRAFGLOBALS
        MOVE.L  (A0),A0                         | POINT TO THEPORT
        TST     PNVIS(A0)                       | IS PNVIS NEG ?
        BMI.B   DRAWRGN_EXIT                    | YES, QUIT
        PEA.L   PORTBITS(A0)                    | PUSH SRCBITS
        MOVE.L  (SP),-(SP)                      | PUSH DSTBITS
        PEA.L   0x8(A0)                         | PUSH PORTBITS+BOUNDS (SRCRECT)
        MOVE.L  (SP),-(SP)                      | PUSH DSTRECT
        MOVE    0xC(A6),-(SP)                   | PUSH MODE
        MOVE.L  0x8(A6),-(SP)                   | PUSH PAT
        MOVE.L  CLIPRGN(A0),-(SP)               | PUSH CLIPRGN
        MOVE.L  VISRGN(A0),-(SP)                | PUSH VISRGN
        MOVE.L  0xE(A6),-(SP)                   | PUSH RGN
        JSR     RgnBlt(PC)                      | CALL RGNBLT
DRAWRGN_EXIT:
        UNLK    A6                              | RELEASE STACK FRAME
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDA    #0xA,SP                         | STRIP PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER

| .PROC FrRgn,3
| .REF FrRect,NewRgn,CopyRgn,InsetRgn,DiffRgn,DrawRgn
| --------------------------------------------------------
|
| PROCEDURE FrRgn(rgn: RgnHandle; mode: INTEGER; pat: Pattern);
|
| A6 OFFSETS OF PARAMS AFTER LINK:
|
| PARAMSIZE .EQU 10
| RGN .EQU PARAMSIZE+8-4 ;LONG, RGNHANDLE
| MODE .EQU RGN-2 ;WORD
| PAT .EQU MODE-4 ;LONG, ADDR OF PATTERN
| Called during boot.
FrRgn:
.set PARAMSIZE, 10                              | TOTAL BYTES OF PARAMS
.set RGN, PARAMSIZE+8-4                         | LONG, RGNHANDLE
.set MODE, RGN-2                                | WORD
.set PAT, MODE-4                                | LONG, ADDR OF PATTERN

        LINK    A6,#0                           | ESTABLISH STACK FRAME
        MOVEM.L D7/A3-A4,-(SP)                  | SAVE REGS
        MOVE.L  (A5),A4                         | POINT TO GRAFGLOBALS
        MOVE.L  (A4),A3                         | POINT TO THEPORT
        TST     PNVIS(A3)                       | IS PNVIS NEG ?
        BMI.B   FRRGN_DONE                      | YES, QUIT

|
| special case rectangular region for speed.
|
        MOVE.L  0xE(A6),A0                      | GET RGNHANDLE

        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        CMPI    #0xA,(A0)                       | IS REGION RECTANGULAR?
        BNE.B   FRRGN_NOTRECT                   | NO, CONTINUE
        PEA.L   RGNBBOX(A0)                     | YES, PUSH ADDR OF BBOX
        JSR     FrRect(PC)                      | FRAME IT
        BRA.B   FRRGN_DONE                      | AND QUIT

| ----------------------------------------------------------
|
| FRRGN_NOTRECT
|
FRRGN_NOTRECT:
        CLR.L   -(SP)                           | NOTRECT: MAKE ROOM FOR FCN RESULT
        JSR     NewRgn(PC)                      | ALLOCATE TEMPRGN
        MOVE.L  (SP)+,D7                        | PUT TEMPRGN IN D7
        MOVE.L  0xE(A6),-(SP)                   | PUSH RGN
        MOVE.L  D7,-(SP)                        | PUSH TEMPRGN
        JSR     CopyRgn(PC)                     | COPY RGN INTO TEMPRGN
        MOVE.L  D7,-(SP)                        | PUSH TEMPRGN
        MOVE.L  PNSIZE(A3),-(SP)                | PUSH PNSIZE
        JSR     InsetRgn(PC)                    | InsetRgn(tempRgn,pnSize);
        MOVE.L  0xE(A6),-(SP)                   | PUSH RGN
        MOVE.L  D7,-(SP)                        | PUSH TEMPRGN
        MOVE.L  D7,-(SP)                        | PUSH TEMPRGN
        JSR     DiffRgn(PC)                     | DiffRgn(rgn,tempRgn,tempRgn);
        MOVE.L  D7,-(SP)                        | PUSH TEMPRGN
        MOVE    0xC(A6),-(SP)                   | PUSH MODE
        MOVE.L  0x8(A6),-(SP)                   | PUSH PAT
        JSR     DrawRgn(PC)                     | DrawRgn(tempRgn,mode,pat);
        MOVE.L  D7,A0                           | GET TEMPRGN
        _DisposeHandle                          | DISCARD IT

| _DisposHandle ;DISCARD IT
| Called during boot.
FRRGN_DONE:
        MOVEM.L (SP)+,D7/A3-A4                  | DONE: RESTORE REGS
        UNLK    A6                              | RELEASE STACK FRAME
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDA    #0xA,SP                         | STRIP PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER

| .FUNC NewRgn,0
| .REF NewHandle
| ---------------------------------------------------
|
| FUNCTION NewRgn;
| Allocate a new region and set it to the empty region.
|
| Called during boot (4,158 times in 30s trace).
NewRgn:
        MOVEM.L D3/A2,-(SP)                     | SAVE REGS
        CLR.L   -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE    #10,-(SP)                       | PUSH BYTECOUNT=10
        JSR     FASTSLABMODE_CONT(PC)           | ALLOCATE A RELOCATABLE OBJECT
        MOVE.L  (SP)+,A0                        | POP RESULTING HANDLE
        MOVEM.L (SP)+,D3/A2                     | RESTORE REGS
        MOVE.L  A0,0x4(SP)                      | STORE INTO NEWRGN RESULT
        MOVE.L  (A0),A0                         | DE-REFERENCE HANDLE
        MOVE    #10,(A0)+                       | INSTALL RGNSIZE=10
        CLR.L   (A0)+                           | INSTALL RGNBBOX=(0,0,0,0)
        CLR.L   (A0)+                           | CLEAR RGNBBOX BOTTOM,RIGHT
        RTS                                     | return from NewRgn

| RTS ;RETURN TO CALLER
| .PROC DisposeRgn
| ---------------------------------------------------
|
| PROCEDURE DisposeRgn(rgn: RgnHandle);
|
| Called during boot (4,137 times in 30s trace).
DisposRgn:
        MOVE.L  (SP)+,A1                        | pop return addr
        MOVE.L  (SP)+,A0                        | pop handle
        _DisposeHandle                          | DISCARD IT

| _DisposHandle ;discard it
        JMP     (A1)                            | and return

| .PROC OpenRgn,0
| .REF NewHandle,HidePen
| ---------------------------------------------------
|
| PROCEDURE OpenRgn;
|
| Called during boot.
OpenRgn:
        MOVEM.L D3/A2-A4,-(SP)                  | SAVE REGS
        MOVE.L  (A5),A4                         | POINT TO GRAFGLOBALS
        MOVE.L  (A4),A0                         | POINT TO THEPORT
        MOVEQ.L #0x1,D0                         | GET TRUE FOR RGNSAVE
        MOVE.L  D0,RGNSAVE(A0)                  | RGNSAVE := TRUE
        CLR     RGNINDEX(A4)                    | RGNINDEX := 0
        CLR.L   -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE    #256,-(SP)                      | PUSH BYTE COUNT = 256
        MOVE    (SP),RGNMAX(A4)                 | RGNMAX := 256 TOO;
        JSR     FASTSLABMODE_CONT(PC)           | ALLOCATE BUFFER
        MOVE.L  (SP)+,RGNBUF(A4)                | RGNBUF := NEWHANDLE(RGNMAX)
        JSR     HidePen(PC)                     | TURN OFF DRAWING
        MOVEM.L (SP)+,D3/A2-A4                  | RESTORE REGS
        RTS                                     | AND RETURN

| .PROC CloseRgn,1
| .REF ShowPen,SortPoints,CullPoints,PackRgn
| ---------------------------------------------------
|
| PROCEDURE CloseRgn(* dstRgn: RgnHandle *);
| Sort array of inversion points and pack into region.
|
| A6 OFFSETS OF PARAMS AND LOCALS AFTER LINK:
|
| PARAMSIZE .EQU 4 ;TOTAL BYTES OF PARAMETERS
| DSTRGN .EQU PARAMSIZE+8-4 ;LONG, RGNHANDLE
| PTCOUNT .EQU -2 ;WORD
| VARSIZE .EQU PTCOUNT ;SIZE OF LOCAL VARS
| Called during boot.
CloseRgn:
        LINK    A6,#-0x2                        | ESTABLISH STACK FRAME
.set PARAMSIZE, 4                               | TOTAL BYTES OF PARAMETERS
.set DSTRGN, PARAMSIZE+8-4                      | LONG, RGNHANDLE
.set PTCOUNT, -2                                | WORD
.set VARSIZE, PTCOUNT                           | SIZE OF LOCAL VARS

        MOVEM.L D3/A2-A4,-(SP)                  | SAVE REGS
        MOVE.L  (A5),A4                         | POINT TO GRAFGLOBALS
        MOVE.L  (A4),A0                         | POINT TO THEPORT
        TST.L   RGNSAVE(A0)                     | IS RGNSAVE TRUE ?
        BEQ.B   CLOSERGN_DONE                   | NO, ABORT
        CLR.L   RGNSAVE(A0)                     | YES, RGNSAVE := FALSE
        JSR     ShowPen(PC)                     | UNDO THE HIDEPEN FROM OPENRGN
        MOVE    RGNINDEX(A4),D0                 | GET CURRENT RGNINDEX
        LSR     #2,D0                           | DIV BY 4
        MOVE    D0,-0x2(A6)                     | FOR PTCOUNT
        MOVE.L  RGNBUF(A4),A3                   | GET RGNBUF HANDLE
        MOVE.L  (A3),-(SP)                      | PUSH BUF POINTER
        MOVE    D0,-(SP)                        | PUSH PTCOUNT
        JSR     SortPoints(PC)                  | QUICKSORT IN VH ORDER
        MOVE.L  (A3),-(SP)                      | PUSH BUF POINTER
        PEA.L   -0x2(A6)                        | PUSH VAR PTCOUNT
        JSR     CullPoints(PC)                  | CANCEL DUPLICATE PAIRS
        MOVE.L  A3,-(SP)                        | PUSH RGNBUF HANDLE
        MOVE    -0x2(A6),-(SP)                  | PUSH (UPDATED) PTCOUNT
        MOVE.L  0x8(A6),-(SP)                   | PUSH DSTRGN
        JSR     PackRgn(PC)                     | PACK POINTS INTO DSTRGN
        MOVE.L  A3,A0                           | GET RGNBUF HANDLE
        _DisposeHandle                          | DISCARD IT

| _DisposHandle ;DISCARD IT
| Called during boot.
CLOSERGN_DONE:
        MOVEM.L (SP)+,D3/A2-A4                  | DONE: RESTORE REGS
        UNLK    A6                              | RELEASE STACK FRAME
        MOVE.L  (SP)+,(SP)                      | STRIP PARAMETERS
        RTS                                     | return from CLOSERGN_DONE

| .PROC CopyRgn,1
| .REF SetSize
| ---------------------------------------------------
|
| PROCEDURE CopyRgn(* srcRgn,dstRgn: RgnHandle *);
|
| PARAMSIZE .EQU 8
| SRCRGN .EQU PARAMSIZE+8-4 ;RGNHANDLE
| DSTRGN .EQU SRCRGN-4 ;RGNHANDLE
| Called during boot (9,298 times in 30s trace).
CopyRgn:
.set PARAMSIZE, 8                               | TOTAL BYTES OF PARAMS
.set SRCRGN, PARAMSIZE+8-4                      | RGNHANDLE
.set DSTRGN, SRCRGN-4                           | RGNHANDLE

        LINK    A6,#0                           | ESTABLISH STACK FRAME
        MOVE.L  0xC(A6),A0                      | GET SRCRGN HANDLE
        MOVE.L  0x8(A6),A1                      | GET DSTRGN HANDLE
        CMP.L   A0,A1                           | ARE THEY THE SAME?
        BEQ.B   EVEN_EXIT                       | YES, QUIT
        MOVE.L  (A0),A0                         | DE-REFERENCE SRCRGN HANDLE
        MOVE.L  (A1),A1                         | DE-REFERENCE DSTRGN HANDLE
        MOVE    (A0),D0                         | GET SRCRGN SIZE
        CMP     (A1),D0                         | IS DSTRGN SIZE SAME AS SRCRGN SIZE?
        BEQ.B   COPY                            | YES, CONTINUE
        MOVEM.L D0/D3/A2,-(SP)                  | SAVE REGS AND BYTECOUNT
        MOVE.L  0x8(A6),-(SP)                   | PUSH DSTRGN HANDLE
        MOVE    D0,-(SP)                        | PUSH NEWSIZE=SRC SIZE
        JSR     SetHSize(PC)                    | CHANGE SIZE OF DST
        MOVEM.L (SP)+,D0/D3/A2                  | RESTORE REGS AND BYTECOUNT
        MOVE.L  0xC(A6),A0                      | GET SRCRGN HANDLE
        MOVE.L  0x8(A6),A1                      | GET DSTRGN HANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE SRCRGN HANDLE
        MOVE.L  (A1),A1                         | DE-REFERENCE DSTRGN HANDLE
COPY:
        LSR     #2,D0                           | LONGCOUNT := BYTECOUNT DIV 4
        BCC.B   EVEN                            | WAS THERE AN ODD WORD ?
        MOVE    (A0)+,(A1)+                     | YES, DO IT TO MAKE EVEN
        BRA.B   EVEN                            | AND CONTINUE

| ----------------------------------------------------------
|
| COPYRGN_COPYLP
|
| Called during boot (111,099 times in 30s trace).
COPYRGN_COPYLP:
        MOVE.L  (A0)+,(A1)+                     | COPYLP: COPY A LONG OF SRC TO DST
EVEN:
        DBF     D0,COPYRGN_COPYLP               | LOOP FOR ALL LONGS
EVEN_EXIT:
        UNLK    A6                              | RELEASE STACK FRAME
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDQ.W  #0x8,SP                         | STRIP PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER

| .PROC SetEmptyRgn,1
| .REF SetRectRgn
| ---------------------------------------------------
|
| PROCEDURE SetEmptyRgn(rgn: RgnHandle);
|
| Called during boot.
SetEmptyRgn:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        CLR.L   -(SP)                           | PUSH LEFT, TOP
        CLR.L   -(SP)                           | PUSH RIGHT,BOTTOM
        MOVE.L  A0,-(SP)                        | RESTORE RETURN ADDR
        JMP     SetRecRgn(PC)                   | DOUBLE UP ON CODE

| .PROC SetRectRgn,5
| .REF SetSize
| ---------------------------------------------------
|
| PROCEDURE SetRectRgn(rgn: RgnHandle; left,top,right,bottom: INTEGER);
| make a rectangular region from 4 integers.
|
| Called during boot (66,914 times in 30s trace).
SetRecRgn:
        LINK    A6,#0                           | ESTABLISH STACK FRAME
        MOVEM.L D3/A2,-(SP)                     | SAVE REGS
        MOVE.L  0x10(A6),A0                     | GET RGN HANDLE
        MOVE.L  (A0),A1                         | DE-REFERENCE HANDLE
        MOVEQ   #10,D0                          | EXPECTED RGNSIZE = 10
        CMP     (A1),D0                         | IS CURRENT REGION 10 BYTES?
        BEQ.B   SETRECTRGN_OK                   | YES, CONTINUE
        MOVE.L  A0,-(SP)                        | PUSH RGNHANDLE
        MOVE    D0,-(SP)                        | PUSH SIZE = 10 BYTES
        JSR     SetHSize(PC)                    | CHANGE SIZE OF REGION
        MOVE.L  0x10(A6),A0                     | GET RGN HANDLE
        MOVE.L  (A0),A1                         | DE-REFERENCE HANDLE
        MOVE    #0xA,(A1)                       | SET RGNSIZE TO 10
SETRECTRGN_OK:
        MOVE.L  0xC(A6),0x2(A1)                 | SET TOPLEFT
        MOVE.L  0x8(A6),0x6(A1)                 | SET BOTRIGHT
        MOVE    0x4(A1),D0                      | GET LEFT
        CMP     0x8(A1),D0                      | COMPARE TO RIGHT
        BGE.B   SETRECTRGN_EMPTY                | YES, SET TO EMPTY
        MOVE    0x2(A1),D0                      | GET TOP
        CMP     0x6(A1),D0                      | COMPARE TO BOTTOM
        BLT.B   SETRECTRGN_DONE                 | YES, CONTINUE
SETRECTRGN_EMPTY:
        CLR.L   0x2(A1)                         | EMPTY TOPLEFT
        CLR.L   0x6(A1)                         | EMPTY BOTRIGHT
SETRECTRGN_DONE:
        MOVEM.L (SP)+,D3/A2                     | DONE: RESTORE REGS
        UNLK    A6                              | RELEASE STACK FRAME
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDA    #0xC,SP                         | STRIP PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER

| .PROC RectRgn,2
| .REF SetRectRgn
| ---------------------------------------------------
|
| PROCEDURE RectRgn(rgn: RgnHandle; r: Rect);
| make a rectangular region from a rectangle
|
| Called during boot (66,892 times in 30s trace).
RectRgn:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF RECT
        MOVE.L  (A1)+,-(SP)                     | PUSH LEFT,TOP
        MOVE.L  (A1)+,-(SP)                     | PUSH RIGHT,BOTTOM
        MOVE.L  A0,-(SP)                        | RESTORE RETURN ADDR
        JMP     SetRecRgn(PC)                   | DOUBLE UP ON CODE

| .PROC OffsetRgn
| ---------------------------------------------------------
|
| PROCEDURE OffsetRgn(rgn: RgnHandle; dh,dv: INTEGER);
|
| Called during boot.
OfsetRgn:
        MOVE.L  (SP)+,A1                        | POP RETURN ADDR
        MOVE    (SP)+,D1                        | POP DV
        MOVE    (SP)+,D0                        | POP DH
        MOVE.L  (SP)+,A0                        | POP RGN HANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        ADDQ.W  #0x2,A0                         | SKIP REGION SIZE

| ------------------------------------------------------
|
| OFFSET THE BOUNDING BOX
|
        ADD     D1,(A0)+                        | ADD DV TO TOP
        ADD     D0,(A0)+                        | ADD DH TO LEFT
        ADD     D1,(A0)+                        | ADD DV TO BOTTOM
        ADD     D0,(A0)+                        | ADD DH TO RIGHT
        CMPI    #0xA,-0xA(A0)                   | IS REGION RECTANGULAR?

| ---------------------------------------------------------------------
|
| IF NON-RECTANGULAR REGION, OFFSET THE COORDINATES TOO.
|
        BEQ.B   OFFSETRGN_DONE                  | IF SO, WE'RE ALL DONE
OFFSETRGN_NXTVERT:
        ADD     D1,(A0)+                        | NXTVERT: OFFSET VERTICAL COORD DV
OFFSETRGN_NXTHOR:
        ADD     D0,(A0)+                        | NXTHOR: OFFSET LEFT COORD DH
        ADD     D0,(A0)+                        | OFFSET RIGHT COORD DH
        CMPI    #0x7FFF,(A0)                    | IS HORIZ END MARKER?
        BNE.B   OFFSETRGN_NXTHOR                | NO, LOOP
        ADDQ.W  #0x2,A0                         | SKIP REGION SIZE
        CMPI    #0x7FFF,(A0)                    | IS HORIZ END MARKER?
        BNE.B   OFFSETRGN_NXTVERT               | NO, LOOP FOR MORE
OFFSETRGN_DONE:
        JMP     (A1)                            | DONE: RETURN

| .PROC InsetRgn,3
| .REF InsetRect,SortPoints
| .REF NewHandle,RgnOp,PackRgn
| ---------------------------------------------------------
|
| PROCEDURE InsetRgn(rgn: RgnHandle; dh,dv: INTEGER);
|
| Inset a region by (dh,dv). Outset if dh or dv neg
|
| A6 OFFSETS OF PARAMS AFTER LINK:
|
| PARAMSIZE .EQU 8
| RGN .EQU PARAMSIZE+8-4 ;LONG, RGNHANDLE
| DH .EQU RGN-2 ;WORD
| DV .EQU DH-2 ;WORD
InsetRgn:
.set PARAMSIZE, 8                               | TOTAL BYTES OF PARAMS
.set RGN, PARAMSIZE+8-4                         | LONG, RGNHANDLE
.set DH, RGN-2                                  | WORD

| .set DV, DH-2 ;WORD
        LINK    A6,#0                           | NO LOCAL VARS
        MOVEM.L D3-D7/A2-A4,-(SP)               | SAVE REGS
        MOVE.L  0x8(A6),D6                      | GET DH AND DV
        BEQ.B   JGOHOME                         | QUIT IF BOTH ARE ZERO
        MOVE.L  0xC(A6),A4                      | GET RGNHANDLE
        MOVE.L  (A4),A3                         | DE-REFERENCE IT
        MOVE    (A3)+,D7                        | GET RGNSIZE
        CMPI    #0xA,D7                         | IS REGION RECTANGULAR?

| --------------------------------------------------------------
|
| IF RECTANGULAR REGION, CALL INSETRECT AND CHECK FOR EMPTY.
|
        BNE.B   INSETRGN_NOTRECT                | NO, CONTINUE
        MOVE.L  A3,-(SP)                        | PUSH ADDR OF RGNBBOX
        MOVE.L  D6,-(SP)                        | PUSH DH AND DV
        JSR     InsetRect(PC)                   | InsetRect(rgn^^.rgnbbox,dh,dv);
        MOVE    LEFT(A3),D0                     | GET BBOX LEFT
        CMP     RIGHT(A3),D0                    | IS LEFT >= RIGHT ?
        BGE.B   INSETRGN_EMPTY                  | YES, RETURN EMPTY RGN
        MOVE    (A3),D0                         | GET BBOX TOP
        CMP     BOTTOM(A3),D0                   | IS TOP >= BOTTOM ?
        BLT.B   JGOHOME                         | NO, CONTINUE
INSETRGN_EMPTY:
        CLR.L   (A3)+                           | EMPTY: SET RGNBBOX TO (0,0,0,0) TO
        CLR.L   (A3)+                           | RETURN EMPTY REGION
JGOHOME:
        BRA.B   INSETRGN_GOHOME                 | ALL DONE

| -----------------------------------------------------
|
| THE REGION IS NOT RECTANGULAR. ALLOCATE A POINT BUFFER IN THE HEAP.
|
INSETRGN_NOTRECT:
        ADD     D7,D7                           | NOTRECT: TRY BYTES NEEDED = RGNSIZE*2
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        MOVE    D7,-(SP)                        | PUSH BYTESNEEDED
        JSR     FASTSLABMODE_CONT(PC)           | ALLOCATE PTBUF
        MOVE.L  (SP)+,A3                        | PUT PTBUF HANDLE IN A3
        BSR.B   HINSET                          | INSET HORIZ AND FLIP
        SWAP    D6                              | GET DV INSTEAD OF DH
        BSR.B   HINSET                          | INSET VERTICAL AND FLIP BACK
        BRA.B   INSETRGN_DONE                   | ALL DONE

| --------------------------------------------------------------------------
|
| LOCAL ROUTINE TO INSET HORIZONTALLY, SWAP H AND V COORDS, AND RE-SORT
|
| RgnOp(rgn,rgn,bufHandle,maxBytes,op,dh,TRUE);
|
HINSET:
        CLR.W   -(SP)                           | ROOM FOR FCN RESULT
        MOVE.L  A4,-(SP)                        | PUSH RGNA = USER RGN
        MOVE.L  A4,-(SP)                        | PUSG RGNB = USER RGN ALSO
        MOVE.L  A3,-(SP)                        | PUSH BUFHANDLE
        MOVE    D7,-(SP)                        | PUSH MAXBYTES
        MOVE    #8,-(SP)                        | PUSH OP = INSET
        MOVE    D6,-(SP)                        | PUSH DH
        ST      -(SP)                           | PUSH OKGROW = TRUE
        JSR     RgnOp(PC)                       | PERFORM REGION OPERATION
        MOVE    (SP)+,D5                        | POP PTCOUNT RESULT

|
| SWAP VERT AND HORIZ COORDS OF ALL INVERSION POINTS
|
        MOVE.L  (A3),A0                         | DE-REFERENCE PTBUF HANDLE
        MOVE    D5,D1                           | COPY PTCOUNT
        BRA.B   SWAP2                           | GO TO LOOP START

| ----------------------------------------------------------
|
| SWAPLP
|
SWAPLP:
        MOVE.L  (A0),D0                         | GET A POINT
        SWAP    D0                              | SWAP ITS COORDINATES
        MOVE.L  D0,(A0)+                        | PUT IT BACK INTO ARRAY
SWAP2:
        DBF     D1,SWAPLP                       | LOOP FOR ALL POINTS

|
| RE-SORT THE POINTS IN V.H ORDER
|
        MOVE.L  (A3),-(SP)                      | PUSH PTBUF PTR
        MOVE    D5,-(SP)                        | PUSH PTCOUNT
        JSR     SortPoints(PC)                  | RE-SORT INTO VH ORDER

|
| PACK THE RESULTING POINTS
|
        MOVE.L  A3,-(SP)                        | PUSH PTBUF HANDLE
        MOVE    D5,-(SP)                        | PUSH PTCOUNT
        MOVE.L  A4,-(SP)                        | PUSH RGN HANDLE
        JSR     PackRgn(PC)                     | PackRgn(ptBuf,ptCount,rgn);
        RTS                                     | RETURN TO LOCAL CALLER

| ----------------------------------------------
|
| DISCARD POINT BUFFER AND QUIT.
|
INSETRGN_DONE:
        MOVE.L  A3,A0                           | DONE: GET PTBUF HANDLE
        _DisposeHandle                          | DISCARD IT

| _DisposHandle ;DISCARD IT
INSETRGN_GOHOME:
        MOVEM.L (SP)+,D3-D7/A2-A4               | GOHOME: RESTORE REGS
        UNLK    A6                              | RELEASE STACK FRAME
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDQ.W  #0x8,SP                         | STRIP PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER

| .FUNC EmptyRgn,1
| .REF EmptyRect
| ---------------------------------------------------
|
| FUNCTION EmptyRgn(rgn: RgnHandle): BOOLEAN;
|
| Called during boot (7,389 times in 30s trace).
EmptyRgn:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP RGNHANDLE
        MOVE.L  (A1),A1                         | DE-REFERENCE HANDLE
        PEA.L   RGNBBOX(A1)                     | PUSH RGNBBOX
        MOVE.L  A0,-(SP)                        | PUSH RETURN ADDR
        JMP     EmptyRect(PC)                   | USE EMPTYRECT CODE

| .FUNC EqualRgn,2
| -------------------------------------------------------
|
| FUNCTION EqualRgn(rgnA,rgnB: RgnHandle): BOOLEAN;
|
| RETURNS TRUE IF RGNA AND RGNB DESCRIBE THE SAME AREA
|
| Called during boot (10,214 times in 30s trace).
EqualRgn:
        MOVE.L  0x4(SP),A0                      | GET RGNA HANDLE
        MOVE.L  0x8(SP),A1                      | GET RGNB HANDLE
        CMP.L   A0,A1                           | ARE THEY THE SAME ?
        BEQ.B   EQUALRGN_LOOP2_OK               | YES, THE REGIONS ARE THE SAME
        MOVE.L  (A0),A0                         | DE-REFERENCE RGN A
        MOVE.L  (A1),A1                         | DE-REFERENCE RGN B
        MOVE    (A0),D0                         | GET RGNSIZE A
        MOVE    D0,D1                           | MAKE AN EXTRA COPY
        LSR     #2,D1                           | DIV BY 4 FOR LONG COUNT
        SUBQ.W  #0x1,D1                         | ADJUST FOR DBF
EQUALRGN_LOOP:
        CMPM.L  (A0)+,(A1)+                     | LOOP: COMPARE A LONG
        DBNE    D1,EQUALRGN_LOOP                | LOOK TILL DIFFERENT OR COUNT
        BNE.B   EQUALRGN_LOOP2_CONT             | DIFFERENT --> FALSE
        ANDI    #0x3,D0                         | GET REMAINING BYTES
        BEQ.B   EQUALRGN_LOOP2_OK               | IF NO MORE, WE MADE IT
EQUALRGN_LOOP2:
        CMPM.B  (A0)+,(A1)+                     | LOOP2: COMPARE A BYTE
        BNE.B   EQUALRGN_LOOP2_CONT             | BR IF DIFFERENT
        SUBQ.W  #0x1,D0                         | ADJUST FOR DBF
        BNE.B   EQUALRGN_LOOP2                  | LOOP LAST 1..3 BYTES
EQUALRGN_LOOP2_OK:
        MOVEQ.L #0x1,D0                         | RETURN TRUE
        BRA.B   EQUALRGN_DONE                   | GO TO DONE

| ----------------------------------------------------------
|
| EQUALRGN_LOOP2_CONT
|
| Called during boot (10,210 times in 30s trace).
EQUALRGN_LOOP2_CONT:
        CLR.L   D0                              | RETURN FALSE
EQUALRGN_DONE:
        MOVE.B  D0,0xC(SP)                      | SET RESULT
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        ADDQ.W  #0x8,SP                         | STRIP PARAMETERS
        JMP     (A0)                            | RETURN

| .PROC SectRgn,3
| .DEF DoRgnOp,UnionRgn,DiffRgn,XorRgn
| .REF EqualRgn,CopyRgn,RSect,RectRgn,SetEmptyRgn
| .REF NewHandle,RgnOp,PackRgn
| ---------------------------------------------------------
|
| PROCEDURE SectRgn(srcRgnA,srcRgnB,dstRgn: RgnHandle);
| calculate the intersection of two regions.
|
| Called during boot (6,491 times in 30s trace).
SectRgn:
        MOVEQ   #0,D0                           | OP = SectScan
        BRA.B   DoRgnOp                         | SHARE COMMON CODE

| ---------------------------------------------------------
|
| PROCEDURE UnionRgn(srcRgnA,srcRgnB,dstRgn: RgnHandle);
| calculate the union of two regions.
|
| Called during boot.
UnionRgn:
        MOVEQ   #4,D0                           | OP = UNION
        BRA.B   DoRgnOp                         | SHARE COMMON CODE

| ---------------------------------------------------------
|
| PROCEDURE DiffRgn(srcRgnA,srcRgnB,dstRgn: RgnHandle);
| calculate the difference A-B of two regions
|
| Called during boot (3,700 times in 30s trace).
DiffRgn:
        MOVEQ   #2,D0                           | OP = DIFF
        BRA.B   DoRgnOp                         | SHARE COMMON CODE

| ---------------------------------------------------------
|
| PROCEDURE XorRgn(srcRgnA,srcRgnB,dstRgn: RgnHandle);
| calculate the exclusive or of two regions
|
| Called during boot.
XorRgn:
        MOVEQ   #6,D0                           | OP = DIFF
        NOP                                     | ALIGN

| ---------------------------------------------------------
|
| PROCEDURE DoRgnOp(srcRgnA,srcRgnB,dstRgn: RgnHandle);
|
| Computes the Intersection, Difference, Union, or Xor of two regions.
|
| enter with op in D0.
| op = 0: SectScan
| 2: DIFF A-B
| 4: UNION
| 6: XOR
|
|
| A6 OFFSETS OF PARAMS AND LOCALS AFTER LINK:
|
| PARAMSIZE .EQU 12
| RGNA .EQU PARAMSIZE+8-4 ;LONG, RGNHANDLE
| RGNB .EQU RGNA-4 ;LONG, RGNHANDLE
| DSTRGN .EQU RGNB-4 ;LONG, RGNHANDLE
|
| TEMPRECT .EQU -8 ;RECT
| VARSIZE .EQU TEMPRECT ;TOTAL LOCALS
|
| Called during boot (10,214 times in 30s trace).
DoRgnOp:
        LINK    A6,#-0x8                        | ESTABLISH STACK FRAME
        MOVEM.L D3-D7/A2-A4,-(SP)               | SAVE REGS
        MOVE    D0,D5                           | COPY OP INTO D5
        MOVE.L  0x10(A6),A2                     | GET RGNA
        MOVE.L  0xC(A6),A3                      | GET RGNB
        MOVE.L  0x8(A6),A4                      | GET DSTRGN
        MOVEQ.L #0x2,D7                         | CONSTANT FOR DIFF OP

|
| ARE THE TWO INPUT REGIONS THE SAME ?
|
        CLR.B   -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE.L  A2,-(SP)                        | PUSH RGNA
        MOVE.L  A3,-(SP)                        | PUSH RGNB
        JSR     EqualRgn(PC)                    | CALL EQUALRGN
        TST.B   (SP)+                           | ARE THEY THE SAME ?
        BEQ.B   XORRGN_NOTSAME                  | NO, CONTINUE

|
| THE TWO REGIONS ARE THE SAME. IF SectScan OR UNION
| THEN COPY RGNA INTO DSTRGN, ELSE ZERO OUT DSTRGN.
|
        AND     D7,D5                           | WAS OP SectScan OR UNION ?
        BNE.B   XORRGN_ZERO                     | NO, ZERO OUT DSTRGN
XORRGN_COPY:
        MOVE.L  A2,-(SP)                        | COPY: PUSH RGNA
        MOVE.L  A4,-(SP)                        | PUSH DSTRGN
        JSR     CopyRgn(PC)                     | COPY RGNA INTO DSTRGN
        BRA.B   JDONE                           | AND QUIT

| ----------------------------------------------------------
|
| XORRGN_ZERO
|
| Called during boot.
XORRGN_ZERO:
        MOVE.L  A4,-(SP)                        | ZERO: PUSH DSTRGN
        JSR     SetEmptyRgn(PC)                 | SET IT TO EMPTY
        BRA.B   JDONE                           | AND QUIT

|
| IF OP = DIFF AND RGNB = EMPTY, COPY RGNA INTO DST
|
| Called during boot (10,210 times in 30s trace).
XORRGN_NOTSAME:
        MOVE.L  (A2),A0                         | NOTSAME: DE-REFERENCE RGNA
        MOVE.L  (A3),A1                         | DE-REFERENCE RGNB
        CMP     D7,D5                           | IS OP = DIFF ?
        BGT.B   UNIXOR                          | NO, ITS UNION OR XOR
        BLT.B   BBOXES                          | NO, IT'S SectScan
        MOVE    0x4(A1),D0                      | GET LEFT
        CMP     0x8(A1),D0                      | COMPARE TO RIGHT
        BGE.B   XORRGN_COPY                     | YES, COPY RGNA INTO DST

|
| IF op = SectScan OR DIFF, THEN INTERSECT THE BOUNDING BOXES.
|
| Called during boot (10,188 times in 30s trace).
BBOXES:
        PEA.L   RGNBBOX(A0)                     | PUSH RGNA^^.RGNBBOX
        PEA.L   RGNBBOX(A1)                     | PUSH RGNB^^.RGNBBOX
        MOVE    D7,-(SP)                        | PUSH NRECTS = 2
        PEA.L   -0x8(A6)                        | PUSH DST = TEMPRECT
        JSR     RSect(PC)                       | CALC INTERSECTION
        BNE.B   NOTEMPTY                        | BR IF RESULT NOT EMPTY

|
| THE BOUNDING BOXES DON'T INTERSECT.
| IF OP = SectScan, THEN RETURN EMPTY.
| IF OP = DIFF, THEN COPY RGNA INTO DSTRGN.
|
        TST     D5                              | IS OP = SectScan ?
        BEQ.B   XORRGN_ZERO                     | YES, RETURN EMPTY
        BRA.B   XORRGN_COPY                     | NO, COPY SRCA INTO DSTRGN

|
| IF OP = SectScan, THEN CHECK FOR BOTH INPUTS RECTANGULAR
|
| Called during boot (10,182 times in 30s trace).
NOTEMPTY:
        MOVE.L  (A2),A0                         | DE-REFERENCE RGNA
        MOVE.L  (A3),A1                         | DE-REFERENCE RGNB
        TST     D5                              | IS OP = SectScan ?
        BNE.B   JDONE_NO_2                      | NO, CONTINUE
        MOVEQ   #10,D0                          | EXPECTED RGNSIZE = 10
        CMP     (A0),D0                         | IS RGNA RECTANGULAR?
        BNE.B   JDONE_NO_2                      | NO, CONTINUE
        CMP     (A1),D0                         | IS DSTRGN SIZE SAME AS SRCRGN SIZE?
        BNE.B   JDONE_NO_2                      | NO, CONTINUE
        MOVE.L  A4,-(SP)                        | PUSH DSTRGN
        PEA.L   -0x8(A6)                        | PUSH TEMPRECT
        JSR     RectRgn(PC)                     | RectRgn(dstRgn,tempRect);
JDONE:
        BRA.B   JDONE_DONE                      | GO TO DONE

| ----------------------------------------------------------
|
| UNIXOR
|
| Called during boot.
UNIXOR:
        MOVE    0x4(A1),D0                      | GET LEFT
        CMP     0x8(A1),D0                      | COMPARE TO RIGHT

|
| OP = UNION OR XOR: IF EITHER REGION IS EMPTY, COPY THE OTHER.
|
        BGE.B   XORRGN_COPY                     | YES, COPY RGNA INTO DST
        MOVE    0x4(A0),D0                      | GET RGNA LEFT
        CMP     0x8(A0),D0                      | COMPARE TO RGNA RIGHT
        BLT.B   JDONE_NO_2                      | NO, CONTINUE
        MOVE.L  A3,A2                           | YES, GET RGNB INSTEAD
        BRA.B   XORRGN_COPY                     | COPY RGNB INTO DST

| ----------------------------------------------------------
|
| JDONE_NO_2
|
| Called during boot (7,414 times in 30s trace).
JDONE_NO_2:
        MOVE    (A0),D4                         | GET RGNA SIZE
        ADD     (A1),D4                         | ADD RGNB SIZE
        ADD     D4,D4                           | TRY DOUBLE FOR BYTECOUNT
        CLR.L   -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE    D4,-(SP)                        | PUSH BYTECOUNT
        JSR     FASTSLABMODE_CONT(PC)           | ALLOCATE PTBUF
        MOVE.L  (SP)+,A3                        | GET PTBUF HANDLE IN A3

|
| PtCount := RgnOp(srcA,srcB,bufHandle,maxBytes,op,0,TRUE);
|
        CLR.W   -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE.L  0x10(A6),-(SP)                  | PUSH RGNA
        MOVE.L  0xC(A6),-(SP)                   | PUSH RGNB
        MOVE.L  A3,-(SP)                        | PUSH BUFHANDLE
        MOVE    D4,-(SP)                        | PUSH MAXBYTES
        MOVE    D5,-(SP)                        | PUSH OP
        CLR.W   -(SP)                           | PUSH DH=0
        ST      -(SP)                           | PUSH OKGROW = TRUE
        JSR     RgnOp(PC)                       | PERFORM REGION OPERATION
        MOVE    (SP)+,D6                        | GET PTCOUNT
        MOVE.L  A3,-(SP)                        | PUSH PTBUF HANDLE
        MOVE    D6,-(SP)                        | PUSH PTCOUNT
        MOVE.L  A4,-(SP)                        | PUSH DSTRGN
        JSR     PackRgn(PC)                     | PackRgn(ptBuf,ptCount,dstRgn);
        MOVE.L  A3,A0                           | GET PTBUF HANDLE
        _DisposeHandle                          | DISCARD IT

| _DisposHandle ;DISCARD IT
| Called during boot (10,214 times in 30s trace).
JDONE_DONE:
        MOVEM.L (SP)+,D3-D7/A2-A4               | DONE: RESTORE REGS
        UNLK    A6                              | RELEASE STACK FRAME
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDA    #0xC,SP                         | STRIP PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER

| .PROC PtInRgn
| ------------------------------------------------------------
|
| FUNCTION PtInRgn(pt: Point; rgn: RgnHandle): BOOLEAN;
|
| TESTS IF A GIVEN POINT IS INSIDE A REGION.
|
| A6 OFFSETS OF PARAMETERS AFTER LINK:
|
| PARAMSIZE .EQU 8 ;SIZE OF PARAMETERS
| RESULT .EQU PARAMSIZE+8 ;BOOLEAN
| PT .EQU RESULT-4 ;POINT, VALUE
| RGN .EQU PT-4 ;LONG, HANDLE
| Called during boot (4,005 times in 30s trace).
PtInRgn:
.set PARAMSIZE, 8                               | SIZE OF PARAMETERS
.set RESULT, PARAMSIZE+8                        | BOOLEAN
.set PT, RESULT-4                               | POINT, VALUE
.set RGN, PT-4                                  | LONG, HANDLE

        LINK    A6,#0                           | ENTRY: NO LOCAL VARS
        MOVE.L  D3,-(SP)                        | SAVE REG
        MOVE    0xE(A6),D1                      | GET PT.H
        MOVE    0xC(A6),D2                      | GET PT.V
        CLR     D3                              | INIT INSIDE:=FALSE

| -----------------------------------------------------------
|
| FIRST CHECK BOUNDING BOX
|
        MOVE.L  0x8(A6),A0                      | GET RGN HANDLE

| -----------------------------------------------------------
|
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        CMP     0x4(A0),D1                      | IS PT.H < BBOX LEFT?
        BLT.B   NEXTHOR_EXIT                    | YES, RETURN FALSE
        CMP     0x8(A0),D1                      | IS PT.H >= BBOX RIGHT?
        BGE.B   NEXTHOR_EXIT                    | YES, RETURN FALSE
        CMP     0x2(A0),D2                      | IS PT.V < BBOX TOP?
        BLT.B   NEXTHOR_EXIT                    | YES, RETURN FALSE
        CMP     0x6(A0),D2                      | IS PT.V >= BBOX BOTTOM?
        BGE.B   NEXTHOR_EXIT                    | YES, RETURN FALSE
        CMPI    #0xA,(A0)                       | IS REGION RECTANGULAR?
        BNE.B   PTINRGN_NO                      | NO, CONTINUE
        NOT     D3                              | YES, RETURN TRUE
        BRA.B   NEXTHOR_EXIT                    | GO TO DONE

| ------------------------------------------------------------------
|
| PT IS INSIDE BOUNDING BOX AND REGION IS NOT RECTANGULAR.
| LOOK AT THE INVERSION POINTS TO DETERMINE IF PT IN REGION.
|
| Called during boot (1,323 times in 30s trace).
PTINRGN_NO:
        LEA.L   RGNDATA(A0),A0                  | POINT TO FIRST VERT COORD
PTINRGN_NEXT:
        CMP     (A0)+,D2                        | NXTVERT: IS NEXT VERT > PT.V ?
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
|
| NEXTHOR_EXIT
|
| Called during boot (4,005 times in 30s trace).
NEXTHOR_EXIT:
        NEG.B   D3                              | DONE: BOOLEAN RESULT IS 0 OR 1
        MOVE.B  D3,0x10(A6)                     | RETURN BOOLEAN FCN RESULT
        MOVE.L  (SP)+,D3                        | RESTORE REG
        UNLK    A6                              | RELEASE STACK FRAME
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDQ.W  #0x8,SP                         | STRIP PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER

| .FUNC RectInRgn,2
| .REF RSect,InitRgn,SeekRgn
| --------------------------------------------------
|
| FUNCTION RectInRgn(r: Rect; rgn: RgnHandle): BOOLEAN;
|
| Returns TRUE if any part of the rectangle intersects the region.
|
|
| A6 OFFSETS OF PARAMETERS AFTER LINK:
|
RectInRgn:
        LINK    A6,#-0x24                       | ESTABLISH STACK FRAME
.set PARAMSIZE, 8                               | TOTAL SIZE OF PARAMETERS
.set RESULT, PARAMSIZE+8                        | BYTE, BOOLEAN
.set RECT, RESULT-4                             | LONG, VAR ADDR
.set RGN, RECT-4                                | LONG, RGNHANDLE

| ------------------------------------------------------
|
| A6 OFFSETS OF LOCAL VARIABLES AFTER LINK:
|
.set MINRECT, -8                                | RECTANGLE
.set SAVESTACK, MINRECT-4                       | LONG
.set STATE, SAVESTACK-RGNREC                    | REGION STATE RECORD
.set VARSIZE, STATE                             | TOTAL SIZE OF VARIABLES

        MOVEM.L D0-D7/A1-A5,-(SP)               | SAVE REGISTERS
        MOVE.L  A7,-0xC(A6)                     | REMEMBER STACK START
        CLR.B   0x10(A6)                        | INIT BOOLEAN RESULT TO FALSE
        MOVE.L  0x8(A6),A1                      | GET REGION HANDLE
        MOVE.L  (A1),A1                         | DE-REFERENCE IT

| --------------------------------------------------------------
|
| FIRST CHECK IF RECTANGLE INTERSECTS BOUNDING BOX OF REGION
|
        MOVE.L  0xC(A6),-(SP)                   | PUSH POINTER TO RECT

| --------------------------------------------------------------
|
        PEA.L   RGNBBOX(A1)                     | PUSH POINTER TO RGN BBOX
        MOVE    #2,-(SP)                        | PUSH NRECTS=2
        PEA.L   -0x8(A6)                        | PUSH ADDR WHERE TO PUT RESULT
        JSR     RSect(PC)                       | CALC INTERSECTION
        BEQ.B   TRUE_EXIT                       | QUIT IF NO INTERSECTION
        CMPI    #0xA,(A1)                       | IS REGION RECTANGULAR?
        BEQ.B   TRUE                            | YES, RETURN TRUE

| ------------------------------------------------------------
|
| THE REGION IS NON-RECTANGULAR AND THE RECTANGLE INTERSECTS
| THE REGION'S BOUNDING BOX. WE WILL PLAY BACK THE PORTION OF
| THE REGION WITHIN MINRECT AND SEE IF ANY PART OF THE REGION
| IS ACTUALLY INSIDE THE RECTANGLE.
|

| -------------------------------------------------
|
| INITIALIZE RGN STATE RECORD AT TOP.
        MOVE.L  A1,A0                           | GET RGNPTR IN A0
        LEA.L   -0x24(A6),A1                    | GET STATE RECORD IN A1
        MOVE    -0x6(A6),D0                     | GET MINRECT LEFT
        MOVE    -0x2(A6),D1                     | GET MINRECT RIGHT
        MOVE    D0,D2                           | BUFLEFT:=MINH
        JSR     InitRgn(PC)                     | INIT RECORD, ALLOCATE BUFFER

| ------------------------------------------------------------
|
| PLAY THE REGION BACK INTO SCAN BUFFER UNTIL IT GETS DOWN TO
| MINRECT, THEN CHECK EACH SCANLINE FOR NON-ZERO PLAYBACK.
| QUIT AND RETURN TRUE IF NON-ZERO FOUND BEFORE RGN GOES BEYOND MINRECT.
|
        MOVE    SCANSIZE(A1),D5                 | GET BUFSIZE= # LONGS -1
        MOVE    -0x8(A6),D0                     | GET MINRECT TOP
        JSR     SeekRgn(PC)                     | SEEK THE REGION TO MINRECT TOP
        MOVE    -0x4(A6),D6                     | GET MINRECT BOTTOM
TESTBUF:
        MOVE.L  SCANBUF(A1),A0                  | POINT TO BUFFER START
        MOVE    D5,D0                           | INIT LOOP COUNT TO BUFSIZE
NXTLONG:
        TST.L   (A0)+                           | IS SCAN BUF NON-ZERO ?
        DBNE    D0,NXTLONG                      | TEST LONGS TILL NON ZERO OR END
        BNE.B   TRUE                            | WE FOUND A NON-ZERO, RETURN TRUE
        MOVE    NEXTV(A1),D0                    | GET NEXT VERTICAL IN RGN
        CMP     D0,D6                           | IS NEXT RGN VERT BEYOND BOTTOM ?
        BLE.B   TRUE_EXIT                       | YES, RETURN FALSE
        JSR     SeekRgn(PC)                     | NO, SEEK TO NEXT VERT CHANGE
        BRA.B   TESTBUF                         | AND SEE IF IT IS NON-ZERO

| ----------------------------------------------------------
|
| TRUE
|
TRUE:
        ADDQ.B  #0x1,0x10(A6)                   | SET BOOLEAN RESULT TO TRUE
TRUE_EXIT:
        MOVE.L  -0xC(A6),SP                     | STRIP SCAN BUFFER IF ANY
        MOVEM.L (SP)+,D0-D7/A1-A5               | RESTORE REGISTERS
        UNLK    A6                              | RELEASE STACK FRAME
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDQ.W  #0x8,SP                         | STRIP PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER

| .FUNC TrimRect,2
| .REF RgnOp
| ------------------------------------------------------
|
| FUNCTION TrimRect(rgn: RgnHandle; VAR dstRect: Rect): CCR TRISTATE;
|
| RESULT IN CONDITION CODES:
|
| = RESULT RECTANGULAR, DSTRECT TRIMMED
| < RESULT EMPTY, DSTRECT NOT MODIFIED
| > RESULT NON-RECT, DSTRECT NOT MODIFIED
|
| If the intersection of rgn and dstRect is rectangular,
| then return EQUAL and put the intersection into dstRect.
| If the intersection is empty or not rectangular, then
| return FALSE and don't modify dstRect.
|
| Does not call the storage allocator.
|
| 1. Fake up a rect rgn on the stack from dstRect
| 2. Call RgnOp with max bytes = 24, OKGROW = FALSE
| 3a. If ptCount = 4 THEN result rect, return TRUE and update dstRect.
| 3b. If ptCount < 4 THEN result empty, return TRUE and clear dstRect.
| 3c. If ptCount > 4 THEN result not rect, return FALSE
|
| Called during boot.
TrimRect:
        LINK    A6,#-0x2A                       | ESTABLISH STACK FRAME
.set PARAMSIZE, 8                               | TOTAL BYTES OF PARAMS
.set RGN, PARAMSIZE+8-4                         | LONG, RGNHANDLE
.set DSTRECT, RGN-4                             | LONG, ADDR OF DSTRECT

.set PTDATA, -24                                | ROOM FOR 6 POINTS
.set PTMASTER, PTDATA-4                         | LONG, FAKE MASTER
.set REGION, PTMASTER-10                        | ROOM FOR RECT RGN DATA
.set RGNMASTER, REGION-4                        | LONG
.set VARSIZE, RGNMASTER                         | SIZE OF LOCAL VARIABLES

        MOVEM.L D0-D2/A1,-(SP)                  | SAVE ALL REGS USED
        LEA.L   -0x18(A6),A0                    | POINT TO BUFFER
        MOVE.L  A0,-0x1C(A6)                    | INSTALL INTO FAKE MASTER
        LEA.L   -0x26(A6),A1                    | POINT TO REGION DATA
        MOVE.L  A1,-0x2A(A6)                    | INSTALL INTO FAKE MASTER
        MOVE    #10,(A1)+                       | INSTALL RGNSIZE = 10
        MOVE.L  0x8(A6),A0                      | POINT TO DSTRECT
        MOVE.L  (A0)+,(A1)+                     | COPY DSTRECT TOPLEFT
        MOVE.L  (A0)+,(A1)+                     | COPY DSTRECT BOTRIGHT

|
| RgnOp(rgn,rectRgn,BufHandle,24,sect,0,FALSE)
|
        CLR.W   -(SP)                           | ROOM FOR FCN RESULT
        MOVE.L  0xC(A6),-(SP)                   | PUSH RGN
        PEA.L   -0x2A(A6)                       | PUSH FAKE RGNHANDLE
        PEA.L   -0x1C(A6)                       | PUSH BUFHANDLE
        MOVE    #24,-(SP)                       | PUSH MAXBYTES = 24
        CLR.L   -(SP)                           | PUSH OP = SectScan, DH = 0
        CLR.B   -(SP)                           | PUSH OKGROW = FALSE
        JSR     RgnOp(PC)                       | RgnOp(rgn,rectRgn,buf,64,op,dh,FALSE);
        MOVE.L  0x8(A6),A0                      | POINT TO DSTRECT
        CMPI    #0x4,(SP)+                      | IS PTCOUNT 4? (RECTANGULAR)
        BNE.B   TRIMRECT_EXIT                   | NO, RETURN < OR > IN CCR
        MOVE.L  -0x18(A6),(A0)+                 | UPDATE DSTRECT.TOPLEFT
        MOVE.L  -0xC(A6),(A0)+                  | UPDATE DSTRECT.BOTRIGHT
        SUB     D0,D0                           | SET EQUAL FLAG
TRIMRECT_EXIT:
        MOVEM.L (SP)+,D0-D2/A1                  | DONE: RESTORE ALL REGS
        UNLK    A6                              | RELEASE STACK FRAME
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR INTO A0
        ADDQ.W  #0x8,SP                         | STRIP PARAMETERS
        JMP     (A0)                            | JUMP THRU A0 TO RETURN

| .PROC MapRgn,3
| .REF MapRect,NewHandle,PutRgn,MapPt
| .REF SortPoints,CullPoints,PackRgn
| -------------------------------------------------------------
|
| PROCEDURE MapRgn(rgn: RgnHandle; fromRect,toRect: Rect);
|
| A6 OFFSETS OF PARAMETERS AND LOCALS AFTER LINK:
|
| PARAMSIZE .EQU 12
| RGN .EQU PARAMSIZE+8-4 ;LONG, RGNHANDLE
| FROMRECT .EQU RGN-4 ;LONG, ADDR OF RECT
| TORECT .EQU FROMRECT-4 ;LONG, ADDR OF RECT
MapRgn:
        LINK    A6,#-0x6                        | ESTABLISH STACK FRAME

| INDEX .EQU -2 ;INTEGER
| SIZE .EQU INDEX-2 ;WORD
| PTCOUNT .EQU SIZE-2 ;WORD
| VARSIZE .EQU PTCOUNT ;TOTAL BYTES
.set PARAMSIZE, 12                              | TOTAL BYTES OF PARAMS
.set RGN, PARAMSIZE+8-4                         | LONG, RGNHANDLE
.set FROMRECT, RGN-4                            | LONG, ADDR OF RECT
.set TORECT, FROMRECT-4                         | LONG, ADDR OF RECT

.set INDEX, -2                                  | INTEGER
.set SIZE, INDEX-2                              | WORD
.set PTCOUNT, SIZE-2                            | WORD
.set VARSIZE, PTCOUNT                           | TOTAL BYTES

        MOVEM.L D3/D6-D7/A2-A4,-(SP)            | SAVE REGS

|
| QUIT FAST IF FROMRECT = TORECT
|
        MOVE.L  0xC(A6),A0                      | POINT TO FROMRECT
        MOVE.L  0x8(A6),A1                      | POINT TO TORECT

        CMPM.L  (A0)+,(A1)+                     | IS TOPLEFT SAME ?
        BNE.B   MAPRGN_NO                       | NO, CONTINUE
        CMPM.L  (A0)+,(A1)+                     | YES, IS BOTRIGHT SAME TOO ?
        BEQ.B   MAPRGN_EXIT                     | IF SO, JUST QUIT

|
| SPECIAL CASE RECTANGULAR RGN
|
MAPRGN_NO:
        MOVE.L  0x10(A6),A4                     | GET RGNHANDLE

|
| SPECIAL CASE RECTANGULAR RGN
|
        MOVE.L  (A4),A0                         | DE-REFERENCE RGN
        CMPI    #0xA,(A0)                       | IS REGION RECTANGULAR?
        BNE.B   MAPRGN_NO_2                     | NO, CONTINUE
        PEA.L   RGNBBOX(A0)                     | YES, PUSH RGNBBOX
        MOVE.L  0xC(A6),-(SP)                   | PUSH FROMRECT
        MOVE.L  0x8(A6),-(SP)                   | PUSH TO RECT
        JSR     MapRect(PC)                     | MapRect(rgn^^.rgnBBox,from,to);
MAPRGN_EXIT:
        BRA.B   MAPRGN_DONE                     | GO TO DONE

| ----------------------------------------------------------
|
| MAPRGN_NO_2
|
MAPRGN_NO_2:
        CLR.L   -(SP)                           | NOTRECT: ROOM FOR FCN RESULT
        MOVE    #256,-(SP)                      | PUSH BYTECOUNT = 256
        MOVE    (SP),-0x4(A6)                   | SIZE := 256 BYTES
        JSR     FASTSLABMODE_CONT(PC)           | ALLOCATE PTBUF
        MOVE.L  (SP)+,A3                        | GET PTBUF HANDLE IN A3
        CLR     -0x2(A6)                        | INDEX := 0
        MOVE.L  A4,-(SP)                        | PUSH RGN
        MOVE.L  A3,-(SP)                        | PUSH PTBUF HANDLE
        PEA.L   -0x2(A6)                        | PUSH VAR INDEX
        PEA.L   -0x4(A6)                        | PUSH VAR SIZE
        JSR     PutRgn(PC)                      | UNPACK RGN INTO INVERSION PTS
        MOVE    -0x2(A6),D7                     | GET INDEX
        LSR     #2,D7                           | PTCOUNT := INDEX DIV 4

|
| MAP ALL INVERSION POINTS
|
        MOVE    D7,D6                           | COPY PTCOUNT FOR LOOP COUNT
        MOVE.L  (A3),A2                         | DE-REFERENCE PTBUF HANDLE
        BRA.B   MAPRGN_LOOP_2                   | GO TO LOOP START

| ----------------------------------------------------------
|
| MAPRGN_LOOP
|
MAPRGN_LOOP:
        MOVE.L  A2,-(SP)                        | LOOP: PUSH ADDR OF AN INV PT
        MOVE.L  0xC(A6),-(SP)                   | PUSH FROMRECT
        MOVE.L  0x8(A6),-(SP)                   | PUSH TORECT
        JSR     MapPt(PC)                       | MAP THIS POINT
        ADDQ.L  #0x4,A2                         | ADVANCE TO NEXT POINT
MAPRGN_LOOP_2:
        DBF     D6,MAPRGN_LOOP                  | LOOP ALL INVERSION POINTS
        MOVE.L  (A3),-(SP)                      | PUSH PTBUF PTR
        MOVE    D7,-(SP)                        | PUSH PTCOUNT
        JSR     SortPoints(PC)                  | SortPoints(ptBuf^,ptCount)
        MOVE.L  (A3),-(SP)                      | PUSH PTBUF PTR
        MOVE    D7,-0x6(A6)                     | PUT PTCOUNT IN MEMORY
        PEA.L   -0x6(A6)                        | PUSH VAR PTCOUNT
        JSR     CullPoints(PC)                  | CullPoints(ptBuf^,ptCount)
        MOVE.L  A3,-(SP)                        | PUSH PTBUF HANDLE
        MOVE    -0x6(A6),-(SP)                  | PUSH PTCOUNT
        MOVE.L  A4,-(SP)                        | PUSH RGN
        JSR     PackRgn(PC)                     | PackRgn(ptBuf,ptCount,rgn);
        MOVE.L  A3,A0                           | PUSH PTBUF HANDLE
        _DisposeHandle                          | DISCARD IT

| _DisposHandle ;DISCARD IT
MAPRGN_DONE:
        MOVEM.L (SP)+,D3/D6-D7/A2-A4            | DONE: RESTORE REGS
        UNLK    A6                              | RELEASE STACK FRAME
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDA    #0xC,SP                         | STRIP PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER


