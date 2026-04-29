|-----------------------------------------------------------
|
|
|     ****   ***   ***   *****  *   *  ****   *****   ***
|     *   *   *   *   *    *    *   *  *   *  *      *   *
|     *   *   *   *        *    *   *  *   *  *      *
|     ****    *   *        *    *   *  ****   ***     ***
|     *       *   *        *    *   *  * *    *          *
|     *       *   *   *    *    *   *  *  *   *      *   *
|     *      ***   ***     *     ***   *   *  *****   ***
|
|

| .PROC StdComment,3
| .REF DPutPicByte,PutPicWord,PutPicData
| ------------------------------------------------------------------
|
| PROCEDURE StdComment(kind,dataSize: INTEGER; dataHandle: Handle);
|
| A6 OFFSETS OF PARAMS AFTER LINK:
|
StdComment:
        LINK    A6,#0x0                         | set up stack frame, reserve 0x0 locals
        MOVEM.L D6-D7,-(SP)                     | save scratch regs to stack
        MOVE.L  (A5),A0                         | A0 := (A5)
        MOVE.L  (A0),A0                         | A0 := (A0)
        TST.L   0x5C(A0)                        | test 0x5C(A0)
        BEQ.B   STDCOMMENT_CONT_2               | if zero -> STDCOMMENT_CONT_2
        MOVE    14(A6),D6                       | D6 := 14(A6)
        MOVE    12(A6),D7                       | D7 := rgnB
        BGT.B   STDCOMMENT_CONT                 | if signed > -> STDCOMMENT_CONT
        MOVE.B  #0xA0,-(SP)                     | push picture opcode kind ($A0)
        JSR     PutPicByte(PC)                  | call PutPicByte
        MOVE    D6,-(SP)                        | push D6
        JSR     PutPicWord(PC)                  | call PutPicWord
        BRA.B   STDCOMMENT_CONT_2               | jump to STDCOMMENT_CONT_2
STDCOMMENT_CONT:
        MOVE.B  #0xA1,-(SP)                     | push picture opcode kind ($A1)
        JSR     PutPicByte(PC)                  | call PutPicByte
        MOVE    D6,-(SP)                        | push D6
        JSR     PutPicWord(PC)                  | call PutPicWord
        MOVE    D7,-(SP)                        | push D7
        JSR     PutPicWord(PC)                  | call PutPicWord
        MOVE.L  8(A6),-(SP)                     | -(SP) := rgnC
        JSR     HLock_Inline(PC)                | call HLock_Inline
        MOVE.L  8(A6),A0                        | A0 := rgnC
        MOVE.L  (A0),-(SP)                      | push (A0)
        MOVE    D7,-(SP)                        | push D7
        JSR     PutPicData(PC)                  | call PutPicData
        MOVE.L  8(A6),-(SP)                     | -(SP) := rgnC
        JSR     HUNLOCK_POP_RTS(PC)             | call HUNLOCK_POP_RTS
STDCOMMENT_CONT_2:
        MOVEM.L (SP)+,D6-D7                     | restore scratch regs from stack
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address into A0
        ADDQ.W  #0x8,SP                         | pop parameter bytes from stack
        JMP     (A0)                            | RTS

| .PROC StdGetPic
| ------------------------------------------------------------------
| PROCEDURE StdGetPic(dataPtr: QDPtr; byteCount: INTEGER);
StdGetPic:
        MOVE.L  (SP)+,A0                        | pop return address into A0
        MOVE    (SP)+,D1                        | pop D1
        MOVE.L  (SP)+,A1                        | pop A1
        MOVE.L  A0,-(SP)                        | push A0
        MOVE.L  (A5),A0                         | A0 := (A5)
        MOVE    -0x9E(A0),D0                    | D0 := -0x9E(A0)
        ADD     D1,-0x9E(A0)                    | -0x9E(A0) += D1
        MOVE.L  -0x9C(A0),A0                    | A0 := -0x9C(A0)
        MOVE.L  (A0),A0                         | A0 := (A0)
        ADDA.W  D0,A0                           | A0 += D0
        BRA.B   STDGETPIC_CONT                  | jump to STDGETPIC_CONT
STDGETPIC_LOOP:
        MOVE.B  (A0)+,(A1)+                     | (A1)+ := (A0)+
STDGETPIC_CONT:
        DBRA    D1,STDGETPIC_LOOP               | loop D1 -> STDGETPIC_LOOP
        RTS                                     | YES, QUIT

| .PROC StdPutPic,1
| .REF SetSize
| ------------------------------------------------------------------
| PROCEDURE StdPutPic(dataPtr: QDPtr; byteCount: INTEGER);
| Append some picture bytes to a growing handle.
| PARAMSIZE .EQU 6
| SRCPTR .EQU PARAMSIZE+8-4 ;LONG
| BYTECOUNT .EQU SRCPTR-2 ;WORD
StdPutPic:
        LINK    A6,#0x0                         | set up stack frame, reserve 0x0 locals
        MOVEM.L D6-D7/A3,-(SP)                  | save scratch regs to stack
        MOVE.L  (A5),A1                         | A1 := (A5)
        MOVE.L  (A1),A1                         | A1 := (A1)
        TST.L   0x5C(A1)                        | test 0x5C(A1)
        BEQ.B   STDPUTPIC_CONT_5                | if zero -> STDPUTPIC_CONT_5
        MOVE.L  0x5C(A1),A1                     | A1 := 0x5C(A1)
        MOVE.L  (A1),A1                         | A1 := (A1)
        MOVE.L  (A1),A3                         | A3 := (A1)
        MOVE.L  (A3),A0                         | A0 := (A3)
        MOVE    8(A6),D6                        | D6 := rgnC
        MOVE    (A0),D0                         | D0 := (A0)
        BMI.B   STDPUTPIC_CONT_5                | if negative -> STDPUTPIC_CONT_5
        ADD     D6,D0                           | D0 += D6
        BPL.B   STDPUTPIC_CONT_2                | if non-negative -> STDPUTPIC_CONT_2
STDPUTPIC_CONT:
        MOVE    #-0x1,(A0)                      | (A0) := #-0x1
        MOVE.L  A3,-(SP)                        | push A3
        MOVE    #0xA,-(SP)                      | push #0xA
        JSR     SetHSize(PC)                    | call SetHSize
        BRA.B   STDPUTPIC_CONT_5                | jump to STDPUTPIC_CONT_5
STDPUTPIC_CONT_2:
        CMP     4(A1),D0                        | compare D0 with 4(A1)
        BLE.B   STDPUTPIC_CONT_3                | if signed <= -> STDPUTPIC_CONT_3
        ADDI    #0x100,D0                       | D0 += #0x100
        BMI.B   STDPUTPIC_CONT                  | if negative -> STDPUTPIC_CONT
        MOVE    D0,4(A1)                        | 4(A1) := D0
        MOVE.L  A3,-(SP)                        | push A3
        MOVE    D0,-(SP)                        | push D0
        JSR     SetHSize(PC)                    | call SetHSize
        MOVE.L  (A3),A0                         | A0 := (A3)
STDPUTPIC_CONT_3:
        MOVE    (A0),D0                         | D0 := (A0)
        ADD     D6,(A0)                         | (A0) += D6
        ADDA.W  D0,A0                           | A0 += D0
        MOVE.L  10(A6),A1                       | A1 := 10(A6)
        BRA.B   STDPUTPIC_CONT_4                | jump to STDPUTPIC_CONT_4
STDPUTPIC_LOOP:
        MOVE.B  (A1)+,(A0)+                     | (A0)+ := (A1)+
STDPUTPIC_CONT_4:
        DBRA    D6,STDPUTPIC_LOOP               | loop D6 -> STDPUTPIC_LOOP
STDPUTPIC_CONT_5:
        MOVEM.L (SP)+,D6-D7/A3                  | restore scratch regs from stack
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address into A0
        ADDQ.W  #0x6,SP                         | pop parameter bytes from stack
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| .PROC PicComment,3
| PROCEDURE PicComment(kind, dataSize: INTEGER; dataHandle: Handle);
| Verb-dispatch via QDProcs commentProc (offset $24).
| Plus equivalent: Pictures.s 201.
PicComment:
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  (A0),A0                         | A0 = thePort
        MOVE.L  0x68(A0),D0                     | D0 = grafProcs
        LEA     StdComment(PC),A0               | _StdComment fallback
        BEQ.B   PICCOMMENT_USESTD               | grafProcs nil -> use std
        MOVE.L  D0,A0                           | A0 = QDProcs ptr
        MOVE.L  0x24(A0),A0                     | A0 = commentProc
PICCOMMENT_USESTD:
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| .FUNC OpenPicture,1
| FUNCTION OpenPicture(picFrame: Rect): PicHandle;
| Allocate PICSAVE record + clipRgn copy + initial 256-byte
| PicHandle. Plus equivalent: Pictures.s 223 (different impl --
| Plus does a 500-byte heap test first; classic skips that).
OpenPicture:
        LINK    A6,#0x0                         | set up stack frame, reserve 0x0 locals
        MOVEM.L A3-A4,-(SP)                     | save scratch regs to stack
        CLR.L   12(A6)                          | rgnB := 0
        MOVE.L  (A5),A4                         | A4 := (A5)
        MOVE.L  (A4),A3                         | A3 := (A4)
        TST.L   0x5C(A3)                        | test 0x5C(A3)
        BNE.W   OPENPICTURE_DONE                | BRANCH IF BLACK
        JSR     HidePen(PC)                     | call HidePen
        CLR.L   -(SP)                           | push zero word
        MOVE    #0x5C,-(SP)                     | push #0x5C
        JSR     NewHandle_Inline(PC)            | call NewHandle_Inline
        MOVE.L  (SP)+,A4                        | pop A4
        MOVE.L  A4,0x5C(A3)                     | thePort.picSave := A4
        CLR.L   -(SP)                           | push zero word
        JSR     NewRgn(PC)                      | allocate region handle
        CLR.L   -(SP)                           | push zero word
        MOVE    #0x100,-(SP)                    | push #0x100
        JSR     NewHandle_Inline(PC)            | call NewHandle_Inline
        MOVE.L  (SP)+,A1                        | pop A1
        MOVE.L  A1,12(A6)                       | rgnB := A1
        MOVE.L  (A4),A4                         | A4 := (A4)
        MOVE.L  A1,(A4)+                        | (A4)+ := A1
        MOVE.L  (A1),A1                         | A1 := (A1)
        MOVE    #0xA,(A1)+                      | (A1)+ := #0xA
        MOVE.L  8(A6),A0                        | A0 := rgnC
        MOVE.L  (A0)+,(A1)+                     | (A1)+ := (A0)+
        MOVE.L  (A0)+,(A1)+                     | (A1)+ := (A0)+
        MOVE    #0x100,(A4)+                    | (A4)+ := #0x100
        MOVE.L  (SP)+,(A4)+                     | pop (A4)+
        CLR.L   (A4)+                           | clear (A4)+
        CLR.L   (A4)+                           | clear (A4)+
        CLR.L   (A4)+                           | clear (A4)+
        MOVE    #0x1,(A4)+                      | (A4)+ := #0x1
        CLR     (A4)+                           | clear (A4)+
        CLR.L   (A4)+                           | clear (A4)+
        MOVE.L  #0x10001,D0                     | D0 := #0x10001
        MOVE.L  D0,(A4)+                        | (A4)+ := D0
        MOVE.L  D0,(A4)+                        | (A4)+ := D0
        CLR.L   (A4)+                           | clear (A4)+
        CLR.L   (A4)+                           | clear (A4)+
        MOVE.L  D0,(A4)+                        | (A4)+ := D0
        MOVE    #0x8,(A4)+                      | (A4)+ := #0x8
        MOVEQ.L #-0x1,D0                        | D0 := #-0x1
        MOVE.L  D0,(A4)+                        | (A4)+ := D0
        MOVE.L  D0,(A4)+                        | (A4)+ := D0
        MOVE.L  D0,(A4)+                        | (A4)+ := D0
        MOVE.L  D0,(A4)+                        | (A4)+ := D0
        CLR.L   (A4)+                           | clear (A4)+
        CLR.L   (A4)+                           | clear (A4)+
        CLR.L   (A4)+                           | clear (A4)+
        MOVE.L  16(A3),(A4)+                    | (A4)+ := thePort.portRect
        MOVE.L  #0x21,(A4)+                     | (A4)+ := #0x21
        MOVE.L  #0x1E,(A4)+                     | (A4)+ := #0x1E
        MOVE    #0x1101,-(SP)                   | push #0x1101
        JSR     PutPicWord(PC)                  | emit word into picture stream
OPENPICTURE_DONE:
        MOVEM.L (SP)+,A3-A4                     | restore scratch regs from stack
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,(SP)                      | pop (SP)
        RTS                                     | YES, QUIT

| ----------------------------------------------------------
| .PROC ClosePicture,0
| PROCEDURE ClosePicture; finalize the picture being saved.
| Plus equivalent: Pictures.s 337.
ClosePicture:
        MOVEM.L D6-D7/A3-A4,-(SP)               | save regs
        MOVE.L  (A5),A4                         | A4 = QD globals
        MOVE.L  (A4),A3                         | A3 = thePort
        MOVE.L  0x5C(A3),D7                     | D7 = PICSAVE
        BEQ.B   CLOSEPICTURE_GOHOME             | not saving -> exit
        MOVE.B  #0xFF,-(SP)                     | push end-of-picture opcode ($FF)
        JSR     PutPicByte(PC)                  | call PutPicByte
        MOVE.L  D7,A0                           | A0 = PICSAVE
        MOVE.L  (A0),A0                         | dereference
        MOVE.L  6(A0),D6                        | D6 = picClipRgn
        MOVE.L  (A0),A1                         | A1 = picHandle
        MOVE.L  (A1),A0                         | dereference
        MOVE    (A0),D0                         | D0 = picSize
        BMI.B   CLOSEPICTURE_OVERFLO            | overflow flag -> skip trim
        MOVE.L  A1,-(SP)                        | push picHandle
        MOVE    D0,-(SP)                        | push final size
        JSR     SetHSize(PC)                    | trim to exact size
CLOSEPICTURE_OVERFLO:
        MOVE.L  D6,-(SP)                        | push picClipRgn
        JSR     NEWRGN_CONT(PC)                 | DisposeHandle wrapper
        MOVE.L  D7,-(SP)                        | push PICSAVE handle
        JSR     KillPicture(PC)                 | dispose PICSAVE
        CLR.L   0x5C(A3)                        | PICSAVE := nil
        JSR     ShowPen(PC)                     | resume drawing
CLOSEPICTURE_GOHOME:
        MOVEM.L (SP)+,D6-D7/A3-A4               | restore regs
        RTS                                     | return
        JMP     KillPicture(PC)                 | tail-call: dispose picture and return

| ----------------------------------------------------------
| .PROC DrawPicture,2
| .REF PicItem,KillPicture
| PROCEDURE DrawPicture(myPicture: PicHandle; dstRect: Rect);
| Play back a saved picture, scaling to dstRect. The body extends
| into Pictures.s (which starts mid-routine). Plus equivalent:
| Pictures.s 385.
| Called during boot.
DrawPicture:
        LINK    A6,#-0xA0                       | set up stack frame
        MOVEM.L D3-D7/A2-A4,-(SP)               | save scratch regs to stack
        MOVE.L  (A5),A4                         | A4 := (A5)
        MOVE.L  (A4),A3                         | A3 := (A4)
        MOVE.L  8(A6),A0                        | A0 := rgnC
        MOVE    6(A0),D0                        | D0 := 6(A0)
        SUB     2(A0),D0                        | D0 -= 2(A0)
        BLE.W   DRAWPICTURE_GOHOME              | if signed <= -> DRAWPICTURE_GOHOME
        MOVE    D0,-14(A6)                      | -14(A6) := D0
        MOVE    4(A0),D0                        | D0 := 4(A0)
        SUB     (A0),D0                         | D0 -= (A0)
        BLE.W   DRAWPICTURE_GOHOME              | if signed <= -> DRAWPICTURE_GOHOME
        MOVE    D0,-16(A6)                      | -16(A6) := D0
        LEA.L     -24(A6),A1                    | A1 = &-24(A6)
        MOVE.L  (A0)+,(A1)+                     | (A1)+ := (A0)+
        MOVE.L  (A0)+,(A1)+                     | (A1)+ := (A0)+
        MOVE.L  12(A6),A0                       | A0 := rgnB
        MOVE.L  (A0),A0                         | A0 := (A0)
        LEA.L     2(A0),A0                      | A0 = &2(A0)
        MOVE    6(A0),D0                        | D0 := 6(A0)
        SUB     2(A0),D0                        | D0 -= 2(A0)
        BLE.W   DRAWPICTURE_GOHOME              | if signed <= -> DRAWPICTURE_GOHOME
        MOVE    D0,-10(A6)                      | -10(A6) := D0
        MOVE    4(A0),D0                        | D0 := 4(A0)
        SUB     (A0),D0                         | D0 -= (A0)
        BLE.W   DRAWPICTURE_GOHOME              | if signed <= -> DRAWPICTURE_GOHOME
        MOVE    D0,-12(A6)                      | -12(A6) := D0
        LEA.L     -0x20(A6),A1                  | A1 = &-0x20(A6)
        MOVE.L  (A0)+,(A1)+                     | (A1)+ := (A0)+
        MOVE.L  (A0)+,(A1)+                     | (A1)+ := (A0)+
        MOVE.L  A3,A0                           | A0 := A3
        LEA.L     -0xA0(A6),A1                  | A1 = &scratchPtr
        MOVEQ.L #0x35,D0                        | D0 := #0x35
STDPUTPIC_LOOP_2:
        MOVE    (A0)+,(A1)+                     | (A1)+ := (A0)+
        DBRA    D0,STDPUTPIC_LOOP_2             | loop D0 -> STDPUTPIC_LOOP_2
        CLR.L   -0xA8(A4)                       | clear -0xA8(A4)
        MOVE.L  12(A6),-0x9C(A4)                | -0x9C(A4) := rgnB
        MOVE    #0xA,-0x9E(A4)                  | -0x9E(A4) := #0xA
        LEA.L     -0x34(A6),A0                  | A0 = &thingRect
        CLR.L   (A0)+                           | stuff picFrame = (0,0,0,0)
        CLR.L   (A0)+                           | all 8 bytes of picFrame
        CLR.L   (A0)+                           | THERECT := (0,0,0,0)
        CLR.L   (A0)+                           | clear (A0)+
        CLR.L   (A0)+                           | PENLOC := (0,0)
        MOVE.L  28(A3),-4(A6)                   | playState := thePort.clipRgn
        CLR.L   -(SP)                           | push zero word
        JSR     NewRgn(PC)                      | allocate empty region
        MOVE.L  (SP)+,-8(A6)                    | tempHndl := (SP)+
        CLR.L   -(SP)                           | jump via A0
        JSR     NewRgn(PC)                      | allocate empty region
        MOVE.L  (SP)+,28(A3)                    | ALLOCATE TEMP CLIPRGN
        LEA.L     0x20(A3),A0                   | A0 = &thePort.bkPat
        CLR.L   (A0)+                           | BKPAT := WHITE
        CLR.L   (A0)+                           | clear (A0)+
        MOVEQ.L #-0x1,D0                        | D0 := #-0x1
        MOVE.L  D0,(A0)+                        | fillPat := BLACK
        MOVE.L  D0,(A0)+                        | (A0)+ := D0
        CLR.L   (A0)+                           | PNLOC := (0,0)
        MOVE.L  #0x10001,D1                     | D1 := #0x10001
        MOVE.L  D1,(A0)+                        | pnSize := (1,1)
        MOVE    #0x8,(A0)+                      | (A0)+ := #0x8
        MOVE.L  D0,(A0)+                        | pnPat := black
        MOVE.L  D0,(A0)+                        | (A0)+ := D0
        ADDQ.W  #0x2,A0                         | A0 += #0x2
        CLR.L   (A0)+                           | txFont, txFace := 0
        MOVE    #0x1,(A0)+                      | (A0)+ := #0x1
        CLR     (A0)+                           | txSize := 0;
        CLR.L   (A0)+                           | spExtra := 0.0;
        MOVE.L  #0x21,(A0)+                     | (A0)+ := #0x21
        MOVE.L  #0x1E,(A0)+                     | (A0)+ := #0x1E
| LEAVE COLRBIT ALONE
| LEAVE PATSTRETCH ALONE
| LEAVE PICSAVE ALONE
| LEAVE RGNSAVE ALONE
| LEAVE POLYSAVE ALONE
| LEAVE GRAFPROCS ALONE

| ---------------------------------------------------
| NOW DRAW THE PICTURE:
| REPEAT UNTIL NOT PicItem(playState);
MORE:
        CLR.B   -(SP)                           | MAKE ROOM FOR FCN RESULT
        PEA.L     -0x34(A6)                     | push &thingRect
        JSR     PicItem(PC)                     | DRAW ONE PICTURE ITEM
        MOVE.B  (SP)+,D0                        | POP BOOLEAN RESULT
        BNE.B   MORE                            | LOOP TILL FALSE
        MOVE.L  -8(A6),-(SP)                    | -(SP) := tempHndl
        JSR     NEWRGN_CONT(PC)                 | dispose region
        MOVE.L  28(A3),-(SP)                    | push thePort.clipRgn
        JSR     NEWRGN_CONT(PC)                 | dispose region
        LEA.L     -0xA0(A6),A0                  | A0 = &savedFields
        MOVEQ.L #0x35,D0                        | D0 := #0x35
MORE_LOOP:
        MOVE    (A0)+,(A3)+                     | INIT DBRA COUNT
        DBRA    D0,MORE_LOOP                    | LOOP ENTIRE PORT
        CLR.L   -0xA8(A4)                       | RESTORE PATALIGN TO (0,0)
        CLR.L   -0x9C(A4)                       | SET PLAYPIC TO NIL
        CLR     -0x9E(A4)                       | clear -0x9E(A4)
DRAWPICTURE_GOHOME:
        MOVEM.L (SP)+,D3-D7/A2-A4               | RESTORE REGISTERS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address into A0
        ADDQ.W  #0x8,SP                         | pop parameter bytes from stack
        JMP     (A0)                            | RTS
PicItem:
        LINK    A6,#-0x134                      | set up stack frame
        MOVEM.L D3-D7/A2-A4,-(SP)               | SAVE REGISTERS
        MOVE.L  (A5),A4                         | A4 := (A5)
        MOVE.L  (A4),A3                         | A3 := (A4)
        BSR.W   GETUBYTE                        | GET OPCODE BYTE
        MOVE    D0,D7                           | PUT IT IN D7
        CMPI.B  #0xFF,D7                        | end-of-picture sentinel?
        BNE.B   NOTEND                          | NO, CONTINUE
        CLR.B   12(A6)                          | YES, RETURN FALSE
        BRA.W   KILL1_EXIT                      | AND QUIT
NOTEND:
        MOVE.B  #0x1,12(A6)                     | frame := #0x1
        CMPI    #0x20,D7                        | is opcode in fast-skip range?
        BCS.W   NOTEND_OK                       | if carry -> NOTEND_OK
        MOVE.B  D7,D0                           | COPY OPCODE
        ANDI    #0xF0,D0                        | mask D0 with #0xF0
        BTST    #0x3,D7                         | test bit #0x3 of D7
        SNE     -0x28(A6)                       | set if cond: -0x28(A6)
        ANDI    #0x7,D7                         | mask D7 with #0x7
        LSR     #0x3,D0                         | D0 >>= 3 (logical)
        .short  0x303B, 0x0006                  | MOVE.W PICITEM_DISPATCH_TBL(PC,D0.W),D0
        .short  0x4EFB, 0x0002                  | JMP PICITEM_DISPATCH_TBL(PC,D0.W)
PICITEM_DISPATCH_TBL:                           | pic opcode dispatch (17 entries)
        .short  0x0622                          | op 0 (short-skip)
        .short  0x0622                          | op 1 (short-skip)
        .short  0x01B2                          | op 2
        .short  0x02C4                          | op 3
        .short  0x02E0                          | op 4
        .short  0x0304                          | op 5
        .short  0x0320                          | op 6
        .short  0x0348                          | op 7
        .short  0x037C                          | op 8
        .short  0x03B0                          | op 9
        .short  0x0484                          | op 10
        .short  0x0622, 0x0622                  | ops 11, 12 (short-skip)
        .short  0x0622, 0x0622, 0x0622, 0x0622  | ops 13-16 (short-skip)
NOTEND_OK:
        ANDI    #0x1F,D7                        | MASK OUT PARAM OPCODE
        ADD     D7,D7                           | DOUBLE PARAM FOR CASE INDEX
        .short  0x303B, 0x7006                  | MOVE.W PICITEM_OP_TBL(PC,D7.W),D0
        .short  0x4EFB, 0x0002                  | JMP PICITEM_OP_TBL(PC,D0.W)
PICITEM_OP_TBL:                                 | pic-opcode handler offsets (32 entries)
        .short  0x05F2, 0x0040                  | entry 0, 1
        .short  0x009E, 0x00A4                  | entry 2, 3
        .short  0x00AA, 0x00B4                  | entry 4, 5
        .short  0x00C0, 0x00C6                  | entry 6, 7
        .short  0x0116, 0x011E                  | entry 8, 9
        .short  0x0126, 0x012E                  | entry 10, 11
        .short  0x014E, 0x00BA                  | entry 12, 13
        .short  0x0092, 0x0098                  | entry 14, 15
        .short  0x00E6, 0x010E                  | entry 16, 17
        .short  0x05F2, 0x05F2                  | entries 18-19 (unused -> fallback)
        .short  0x05F2, 0x05F2                  | entries 20-21
        .short  0x05F2, 0x05F2                  | entries 22-23
        .short  0x05F2, 0x05F2                  | entries 24-25
        .short  0x05F2, 0x05F2                  | entries 26-27
        .short  0x05F2, 0x05F2                  | entries 28-29
        .short  0x05F2, 0x05F2                  | entries 30-31
| Shared BSR.W tail reached by fall-through from the no-clip handlers
        BSR.W   GETHNDL                         | COPY RGN INTO HANDLE1
        MOVE.L  8(A6),A2                        | POINT TO PLAYSTATE RECORD
        MOVE.L  -4(A6),-(SP)                    | -(SP) := playState
        MOVE.L  0x2C(A2),-(SP)                  | push 0x2C(A2)
XCLIP2:
        JSR     CopyRgn(PC)                     | COPY HANDLE1 INTO THECLIP
        MOVE.L  8(A6),A2                        | POINT TO PLAYSTATE RECORD
        MOVE.L  -4(A6),-(SP)                    | PUSH HANDLE1 TEMP
        PEA.L     20(A2)                        | PUSH FROMRECT
        PEA.L     28(A2)                        | PUSH TORECT
        JSR     MapRgn(PC)                      | MAP RGN INTO DST COORDS
        MOVE.L  8(A6),A2                        | POINT TO PLAYSTATE RECORD
        MOVE.L  -4(A6),-(SP)                    | PUSH MAPPED RGN
        MOVE.L  0x30(A2),-(SP)                  | PUSH ORIGINAL CLIP
        MOVE.L  28(A3),-(SP)                    | PUSH DST = THEPORT^.CLIPRGN
        JSR     SectRgn(PC)                     | PUT INTERSECT INTO CLIPRGN
        BRA.W   KILL1                           | DISCARD HANDLE1 AND QUIT
GET8:
        MOVEQ.L #0x8,D6                         | set field size = 8 bytes
        BRA.W   GETDONE                         | COPY 8 BYTES AND QUIT
GET4:
        MOVEQ.L #0x4,D6                         | set field size = 4 bytes
        BRA.W   GETDONE                         | COPY 4 BYTES AND QUIT
GET2:
        MOVEQ.L #0x2,D6                         | BYTECOUNT = 2
        BRA.W   GETDONE                         | COPY 2 BYTES AND QUIT
        LEA.L     0x50(A3),A3                   | A3 = &thePort.fgColor
        BRA.B   GET4                            | GET FOREGROUND COLOR
        LEA.L     0x54(A3),A3                   | A3 = &thePort.bkColor
        BRA.B   GET4                            | GET BACKGROUND COLOR
        LEA.L     0x20(A3),A3                   | A3 = &thePort.bkPat
        BRA.B   GET8                            | GET BKPAT
        LEA.L     0x44(A3),A3                   | A3 = &thePort.txFont
        BRA.B   GET2                            | GET TXFONT
        LEA.L     0x46(A3),A3                   | POINT TO TEXT FACE
        MOVEQ.L #0x1,D6                         | SIZE IS 1 WORD
        BRA.W   GETDONE                         | GET TXFACE
        LEA.L     0x48(A3),A3                   | A3 = &thePort.txMode
        BRA.B   GET2                            | GET TXMODE
        LEA.L     0x4A(A3),A3                   | A3 = &thePort.txSize
        BRA.B   GET2                            | GET TXSIZE
        LEA.L     0x4C(A3),A3                   | A3 = &thePort.spExtra
        BRA.B   GET4                            | GET fixed point SPACE EXTRA
        JSR     GETWORD_NO(PC)                  | GET PNSIZE
        MOVE.L  D0,0x34(A3)                     | INSTALL INTO THEPORT
        PEA.L     0x34(A3)                      | PUSH PEN SIZE
        MOVE.L  8(A6),A2                        | POINT TO PLAYSTATE RECORD
        PEA.L     20(A2)                        | PUSH SOURCE RECT
        PEA.L     28(A2)                        | PUSH DEST RECT
        JSR     ScalePt(PC)                     | SCALE PNSIZE
        BRA.W   KILL1_EXIT                      | GO TO COMMON SCALING
        MOVE.L  8(A6),A3                        | POINT TO PLAYSTATE RECORD
        JSR     GETWORD_NO(PC)                  | GET TEXT NUMER
        MOVE.L  D0,0x24(A3)                     | INSTALL INTO PLAYSTATE
        JSR     GETWORD_NO(PC)                  | GET TEXT DENOM
        MOVE.L  D0,0x28(A3)                     | INSTALL INTO PLAYSTATE
        PEA.L     0x24(A3)                      | PUSH PORT RECT
        PEA.L     20(A3)                        | PUSH PORT BOUNDS
        PEA.L     28(A3)                        | PUSH CLIP REGION
        JSR     ScalePt(PC)                     | SCALE NUMER
        BRA.W   KILL1_EXIT                      | GO TO COMMON SCALING
        BSR.W   GETUBYTE                        | GET VERSION NUMBER BYTE
        BRA.W   KILL1_EXIT                      | AND IGNORE IT
        LEA.L     0x38(A3),A3                   | A3 = &thePort.pnMode
        BRA.W   GET2                            | GET PNMODE
        LEA.L     0x3A(A3),A3                   | A3 = &thePort.pnPat
        BRA.W   GET8                            | GET PNPAT
        LEA.L     0x28(A3),A3                   | A3 = &thePort.fillPat
        BRA.W   GET8                            | GET FILLPAT
        JSR     GETWORD_NO(PC)                  | GET OVAL SIZE
        MOVE.L  8(A6),A2                        | POINT TO PLAYSTATE RECORD
        MOVE.L  D0,16(A2)                       | SAVE NEW POINT
        PEA.L     16(A2)                        | PUSH NEW POINT
        PEA.L     20(A2)                        | PUSH SOURCE RECT
        PEA.L     28(A2)                        | PUSH DEST RECT
        JSR     ScalePt(PC)                     | SCALE OVAL SIZE
        BRA.W   KILL1_EXIT                      | GO TO COMMON SCALING
        JSR     GETWORD_NO(PC)                  | GET DH,DV
        MOVE.L  8(A6),A2                        | POINT TO PLAYSTATE RECORD
        ADD     D0,20(A2)                       | ADD DV TO FROMRECT
        ADD     D0,24(A2)                       | ADJUST RECT LEFT
        ADD     D0,-0xA8(A4)                    | AND TO PATALIGN
        SWAP    D0                              | GET DH IN LO WORD
        ADD     D0,22(A2)                       | ADD DH TO FROMRECT
        ADD     D0,26(A2)                       | ADJUST RECT RIGHT
        ADD     D0,-0xA6(A4)                    | AND TO PATALIGN
        MOVE.L  0x2C(A2),-(SP)                  | PUSH THECLIP
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        JSR     NewRgn(PC)                      | ALLOCATE A TEMP RGN
        MOVE.L  (SP),-4(A6)                     | PUT IN HANDLE1
        BRA.W   XCLIP2                          | COPY, MAP, SectScan, AND DISCARD
        TST.B   -0x28(A6)                       | test scratchByte
        BNE.W   TEXTOP                          | YES, DO IT
        MOVE.L  8(A6),A2                        | POINT TO PLAYSTATE RECORD
        MOVE.L  8(A2),D0                        | NO, GET PREVIOUS LINE ENDPOINT
        BTST    #0x0,D7                         | test bit #0x0 of D7
        BNE.B   LNFROM                          | if non-zero -> LNFROM
        BSR.W   GETWORD_NO                      | NO, GET NEW STARTPT
LNFROM:
        MOVE.L  D0,0x30(A3)                     | thePort.pnLoc := D0
        MOVE.L  D0,-0x2C(A6)                    | -0x2C(A6) := D0
        MOVE.L  8(A6),A2                        | POINT TO PLAYSTATE RECORD
        PEA.L     0x30(A3)                      | push &thePort.pnLoc
        PEA.L     20(A2)                        | push effective addr 20(A2)
        PEA.L     28(A2)                        | push effective addr 28(A2)
        JSR     MapPt(PC)                       | MAP STARTPT
        BTST    #0x1,D7                         | test bit #0x1 of D7
        BNE.B   SHORTLN                         | if non-zero -> SHORTLN
        BSR.W   GETWORD_NO                      | NO, GET NEWPT
        MOVE.L  D0,-0x2C(A6)                    | -0x2C(A6) := D0
        BRA.B   LNOK                            | AND CONTINUE
SHORTLN:
        BSR.W   GETSBYTE                        | GET A SIGNED BYTE
        ADD     D0,-0x2A(A6)                    | ADD TO STARTPT.H
        BSR.W   GETSBYTE                        | GET A SIGNED BYTE
        ADD     D0,-0x2C(A6)                    | ADD TO STARTPT.V
LNOK:
        MOVE.L  8(A6),A2                        | POINT TO PLAYSTATE RECORD
        MOVE.L  -0x2C(A6),8(A2)                 | 8(A2) := -0x2C(A6)
        PEA.L     -0x2C(A6)                     | push effective addr -0x2C(A6)
        PEA.L     20(A2)                        | push effective addr 20(A2)
        PEA.L     28(A2)                        | push effective addr 28(A2)
        JSR     MapPt(PC)                       | MAP NEWPT
        MOVE.L  -0x2C(A6),-(SP)                 | push -0x2C(A6)
        LEA     StdLine(PC),A0                  | POINT TO STANDARD PROC
        MOVE.L  0x68(A3),D0                     | D0 := thePort.grafProcs
        BEQ.W   CALL0                           | if zero -> CALL0
        MOVE.L  D0,A0                           | A0 := D0
        MOVE.L  4(A0),A0                        | NO, GET PROCPTR
        BRA.W   CALL0                           | -> already-allocated path
TEXTOP:
        ANDI    #0x3,D7                         | mask D7 with #0x3
        BEQ.B   LONGTXT                         | if zero -> LONGTXT
        BTST    #0x0,D7                         | test bit #0x0 of D7
        BEQ.B   PICITEM_DHOK                    | YES, USE LONG FORMAT
        BSR.W   GETUBYTE                        | GET DH 0..255
        MOVE.L  8(A6),A2                        | POINT TO PLAYSTATE RECORD
        ADD     D0,14(A2)                       | 14(A2) += D0
PICITEM_DHOK:
        BTST    #0x1,D7                         | test bit #0x1 of D7
        BEQ.B   TEXTOP2                         | if zero -> TEXTOP2
        BSR.W   GETUBYTE                        | GET DV 0..255
        MOVE.L  8(A6),A2                        | POINT TO PLAYSTATE RECORD
        ADD     D0,12(A2)                       | 12(A2) += D0
        BRA.B   TEXTOP2                         | SHARE CODE
LONGTXT:
        BSR.W   GETWORD_NO                      | GET TXLOC, UNMAPPED
        MOVE.L  8(A6),A2                        | POINT TO PLAYSTATE RECORD
        MOVE.L  D0,12(A2)                       | SAVE IN TEXTLOC
TEXTOP2:
        BSR.W   GETUBYTE                        | GET TEXT LENGTH 0..255
        MOVE    D0,D6                           | SAVE LENGTH IN D6
        PEA.L     -0x12C(A6)                    | PUSH ADDR OF TEXT BUF
        MOVE    D6,-(SP)                        | PUSH BYTECOUNT
        JSR     GetPicData(PC)                  | GET THE TEXT
        MOVE.L  8(A6),A2                        | POINT TO PLAYSTATE RECORD
        MOVE.L  12(A2),0x30(A3)                 | COPY TEXTLOC INTO PNLOC
        PEA.L     0x30(A3)                      | PUSH PEN LOCATION
        PEA.L     20(A2)                        | PUSH SOURCE RECT
        PEA.L     28(A2)                        | PUSH DEST RECT
        JSR     MapPt(PC)                       | MAP PNLOC
        MOVE    D6,-(SP)                        | PUSH CHARACTER COUNT
        PEA.L     -0x12C(A6)                    | PUSH ADDRESS OF TEXT
        MOVE.L  8(A6),A2                        | POINT TO PLAYSTATE RECORD
        MOVE.L  0x24(A2),-(SP)                  | PUSH NUMER
        MOVE.L  0x28(A2),-(SP)                  | PUSH DENOM
        LEA     StdText(PC),A0                  | POINT TO STANDARD PROC
        MOVE.L  0x68(A3),D0                     | D0 := thePort.grafProcs
        BEQ.W   CALL0                           | if zero -> CALL0
        MOVE.L  D0,A0                           | A0 := D0
        MOVE.L  (A0),A0                         | A0 := (A0)
        BRA.W   CALL0                           | jump to CALL0
        MOVE.B  D7,-(SP)                        | PUSH VERB
        BSR.W   GETRECT                         | GET AND PUSH DSTRECT
        LEA     StdRect(PC),A0                  | POINT TO STANDARD PROC
        MOVE.L  0x68(A3),D0                     | D0 := thePort.grafProcs
        BEQ.W   CALL0                           | if zero -> CALL0
        MOVE.L  D0,A0                           | A0 := D0
        MOVE.L  8(A0),A0                        | NO, GET PROCPTR
        BRA.W   CALL0                           | jump to CALL0
        MOVE.B  D7,-(SP)                        | PUSH VERB
        BSR.W   GETRECT                         | GET AND PUSH DSTRECT
        MOVE.L  8(A6),A2                        | POINT TO PLAYSTATE RECORD
        MOVE.L  16(A2),-(SP)                    | PUSH OVHT,OVWD
        LEA     StdRRect(PC),A0                 | POINT TO STANDARD PROC
        MOVE.L  0x68(A3),D0                     | D0 := thePort.grafProcs
        BEQ.W   CALL0                           | if zero -> CALL0
        MOVE.L  D0,A0                           | A0 := D0
        MOVE.L  12(A0),A0                       | NO, GET PROCPTR
        BRA.W   CALL0                           | jump to CALL0
        MOVE.B  D7,-(SP)                        | PUSH VERB
        BSR.W   GETRECT                         | GET AND PUSH DSTRECT
        LEA     StdOval(PC),A0                  | POINT TO STANDARD PROC
        MOVE.L  0x68(A3),D0                     | D0 := thePort.grafProcs
        BEQ.W   CALL0                           | if zero -> CALL0
        MOVE.L  D0,A0                           | A0 := D0
        MOVE.L  16(A0),A0                       | NO, GET PROCPTR
        BRA.W   CALL0                           | jump to CALL0
        MOVE.B  D7,-(SP)                        | PUSH VERB
        BSR.W   GETRECT                         | GET AND PUSH DSTRECT
        BSR.W   GETWORD                         | GET STARTANGLE
        MOVE    D0,-(SP)                        | PUSH STARTANGLE
        BSR.W   GETWORD                         | GET ARCANGLE
        MOVE    D0,-(SP)                        | PUSH ARCANGLE
        LEA     StdArc(PC),A0                   | POINT TO STANDARD PROC
        MOVE.L  0x68(A3),D0                     | D0 := thePort.grafProcs
        BEQ.W   CALL0                           | if zero -> CALL0
        MOVE.L  D0,A0                           | A0 := D0
        MOVE.L  20(A0),A0                       | NO, GET PROCPTR
        BRA.W   CALL0                           | jump to CALL0
        BSR.W   GETHNDL                         | COPY POLY INTO HANDLE1
        MOVE.L  -4(A6),-(SP)                    | -(SP) := playState
        MOVE.L  8(A6),A2                        | POINT TO PLAYSTATE RECORD
        PEA.L     20(A2)                        | PUSH FROMRECT
        PEA.L     28(A2)                        | PUSH TORECT
        JSR     MapPoly(PC)                     | MAP POLY INTO DST COORDS
        MOVE.B  D7,-(SP)                        | PUSH VERB
        MOVE.L  -4(A6),-(SP)                    | -(SP) := playState
        LEA     StdPoly(PC),A0                  | POINT TO STANDARD PROC
        MOVE.L  0x68(A3),D0                     | D0 := thePort.grafProcs
        BEQ.W   CALL1                           | if zero -> CALL1
        MOVE.L  D0,A0                           | A0 := D0
        MOVE.L  24(A0),A0                       | NO, GET PROCPTR
        BRA.W   CALL1                           | jump to CALL1
        BSR.W   GETHNDL                         | COPY RGN INTO HANDLE1
        MOVE.L  -4(A6),-(SP)                    | -(SP) := playState
        MOVE.L  8(A6),A2                        | POINT TO PLAYSTATE RECORD
        PEA.L     20(A2)                        | PUSH FROMRECT
        PEA.L     28(A2)                        | PUSH TORECT
        JSR     MapRgn(PC)                      | MAP RGN INTO DSTRECT COORDS
        MOVE.B  D7,-(SP)                        | PUSH VERB
        MOVE.L  -4(A6),-(SP)                    | -(SP) := playState
        LEA     StdRgn(PC),A0                   | POINT TO STANDARD PROC
        MOVE.L  0x68(A3),D0                     | D0 := thePort.grafProcs
        BEQ.W   CALL1                           | if zero -> CALL1
        MOVE.L  D0,A0                           | NOPACK: PUSH MASTER
        MOVE.L  28(A0),A0                       | PUSH BYTECOUNT
        BRA.W   CALL1                           | jump to CALL1
        PEA.L     -0x22(A6)                     | PUSH LOCAL RECT
        MOVE    #0x1A,-(SP)                     | PUSH BYTECOUNT = 26
        JSR     GetPicData(PC)                  | GET ROWBYTES,BOUNDS,SRC,DST
        MOVE.L  8(A6),A2                        | POINT TO PLAYSTATE RECORD
        PEA.L     -16(A6)                       | PUSH LOCAL POINT
        PEA.L     20(A2)                        | PUSH SOURCE RECT
        PEA.L     28(A2)                        | PUSH DEST RECT
        JSR     MapRect(PC)                     | MAP DSTRECT
        PEA.L     -0x26(A6)                     | PUSH SRCBITS
        PEA.L     -24(A6)                       | PUSH ADDR OF SRCRECT
        PEA.L     -16(A6)                       | PUSH ADDR OF DSTRECT
        BSR.W   GETWORD                         | GET MODE
        MOVE    D0,-(SP)                        | PUSH MODE
        TST     D7                              | IS MASKRGN USED ?
        BNE.B   USERGN                          | YES, CONTINUE
        CLR.L   -(SP)                           | NO, PUSH MASKRGN = NIL
        BRA.B   USERGN_CONT                     | AND CONTINUE
USERGN:
        BSR.W   GETHNDL                         | GET MASKRGN INTO HANDLE1
        MOVE.L  -4(A6),-(SP)                    | -(SP) := playState
        MOVE.L  -4(A6),-8(A6)                   | tempHndl := playState
USERGN_CONT:
        MOVE    -28(A6),D6                      | D6 := -28(A6)
        SUB     -0x20(A6),D6                    | D6 -= -0x20(A6)
        MOVE    D6,D5                           | COPY HEIGHT
        MULU    -0x22(A6),D5                    | D5 = D5 *u -0x22(A6)
        CLR.L   -(SP)                           | push zero word
        MOVE    D5,-(SP)                        | push D5
        JSR     NewHandle_Inline(PC)            | call NewHandle_Inline
        MOVE.L  (SP),-4(A6)                     | playState := (SP)
        JSR     HLock_Inline(PC)                | call HLock_Inline
        MOVE.L  -4(A6),A0                       | A0 := playState
        TST.B   -0x28(A6)                       | test scratchByte
        BEQ.B   PICITEM_NOPACK                  | CONTINUE IF NOT MEMFULL
        MOVE.L  (A0),-0x134(A6)                 | frameSize := (A0)
        BRA.B   PICITEM_START1                  | GO TO LOOP START

| ----------------------------------------------------------
| PICITEM_MORE1
PICITEM_MORE1:
        BSR.W   GETUBYTE                        | GET PACKED BYTECOUNT
        PEA.L     -0x12C(A6)                    | PUSH ADDR OF BUFFER
        MOVE.L  (SP),-0x130(A6)                 | PUT IN SRCPTR TOO
        MOVE    D0,-(SP)                        | PUSH BYTECOUNT
        JSR     GetPicData(PC)                  | GET PACKED DATA
        PEA.L     -0x130(A6)                    | PUSH VAR SRCPTR
        PEA.L     -0x134(A6)                    | PUSH VAR DSTPTR
        MOVE    -0x22(A6),-(SP)                 | PUSH ROWBYTES
        JSR     UnpackBits(PC)                  | UNPACK INTO HANDLE1 DATA
PICITEM_START1:
        DBRA    D6,PICITEM_MORE1                | LOOP HEIGHT ROWS
        BRA.B   DOBITS                          | CONTINUE
PICITEM_NOPACK:
        MOVE.L  (A0),-(SP)                      | PUSH MASTER
        MOVE    D5,-(SP)                        | PUSH BYTECOUNT
        JSR     GetPicData(PC)                  | pc-relative jsr (was raw .short pair)
DOBITS:
        MOVE.L  -4(A6),A0                       | A0 := playState
        MOVE.L  (A0),-0x26(A6)                  | -0x26(A6) := (A0)
        LEA     StdBits(PC),A0                  | POINT TO STANDARD PROC
        MOVE.L  0x68(A3),D0                     | D0 := thePort.grafProcs
        BEQ.W   BITSOK                          | YES, USE STD PROC
        MOVE.L  D0,A0                           | A0 := D0
        MOVE.L  0x20(A0),A0                     | A0 := 0x20(A0)
BITSOK:
        JSR     (A0)                            | call subroutine via A0
        MOVE.L  -4(A6),-(SP)                    | -(SP) := playState
        JSR     HUNLOCK_POP_RTS(PC)             | call HUNLOCK_POP_RTS
        TST     D7                              | IS MASKRGN USED ?
        BEQ.W   KILL1                           | NO, DISCARD ONLY DATABITS
        BRA.W   KILL2                           | DISCARD MASKRGN & DATABITS
        BSR.W   GETWORD                         | GET COMMENT KIND IN D0
        MOVE    D0,-(SP)                        | PUSH FOR COMMENTPROC
        TST.B   D7                              | IS THIS SHORT FORM ?
        BNE.B   LONGCOM                         | NO, GET MORE
        CLR     -(SP)                           | YES, PUSH DATASIZE = 0
        CLR.L   -(SP)                           | PUSH DATAHANDLE = NIL
        LEA     StdComment(PC),A0               | POINT TO STANDARD PROC
        MOVE.L  0x68(A3),D0                     | D0 := thePort.grafProcs
        BEQ.W   CALL0                           | if zero -> CALL0
        MOVE.L  D0,A0                           | A0 := D0
        MOVE.L  0x24(A0),A0                     | A0 := 0x24(A0)
        BRA.W   CALL0                           | jump to CALL0
LONGCOM:
        BSR.W   GETWORD                         | GET DATASIZE
        MOVE    D0,-(SP)                        | PUSH DATASIZE
        CLR     D4                              | INIT BYTE INDEX FOR GETHND2
        BSR.W   GETHND2                         | GET DATA INTO HANDLE1
        MOVE.L  -4(A6),-(SP)                    | -(SP) := playState
        LEA     StdComment(PC),A0               | POINT TO STANDARD PROC
        MOVE.L  0x68(A3),D0                     | D0 := thePort.grafProcs
        BEQ.W   CALL1                           | if zero -> CALL1
        MOVE.L  D0,A0                           | A0 := D0
        MOVE.L  0x24(A0),A0                     | A0 := 0x24(A0)
        BRA.W   CALL1                           | jump to CALL1
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  -0x7A(A0),A1                    | GET POINTER TO DATA
        MOVE    -0x76(A0),D0                    | GET ROWBYTES
        LEA     LAYOUT(PC),A0                   | POINT TO DATA TABLE
        MOVEQ.L #0x18,D1                        | SET LOOP COUNT
LOOP1:
        MOVE.L  (A0)+,(A1)                      | (A1) := (A0)+
        ADDA.W  D0,A1                           | A1 += D0
        DBRA    D1,LOOP1                        | loop D1 -> LOOP1
LOOP2:
        BRA.B   LOOP2                           | jump to LOOP2

| ----------------------------------------------------------
| LAYOUT
| Embedded 1-bit bitmap data: "STOLEN FROM APPLE COMPUTER"
| Layout:
| - 25 rows
| - 4 bytes per row
| - 32 pixels wide
| So this is a 32 x 25 monochrome image stored uncompressed.
| The routine above copies one longword per scanline.
LAYOUT:
        .byte 0x00, 0x00, 0x00, 0x00            | SCANLINE 0
        .byte 0x7E, 0xE9, 0xD2, 0x00            | SCANLINE 1
        .byte 0x44, 0xA9, 0x1A, 0x00            | SCANLINE 2
        .byte 0x74, 0xA9, 0x96, 0x10            | SCANLINE 3
        .byte 0x14, 0xA9, 0x12, 0x30            | SCANLINE 4
        .byte 0x74, 0xEF, 0xD2, 0x60            | SCANLINE 5
        .byte 0x00, 0x00, 0x00, 0x40            | SCANLINE 6
        .byte 0x77, 0x74, 0x43, 0x58            | SCANLINE 7
        .byte 0x45, 0x57, 0xC7, 0xFC            | SCANLINE 8
        .byte 0x77, 0x55, 0x4F, 0xFE            | SCANLINE 9
        .byte 0x46, 0x54, 0x4F, 0xF8            | SCANLINE 10
        .byte 0x45, 0x74, 0x4F, 0xF0            | SCANLINE 11
        .byte 0x00, 0x00, 0x0F, 0xF0            | SCANLINE 12
        .byte 0x77, 0x74, 0xEF, 0xF8            | SCANLINE 13
        .byte 0x55, 0x54, 0x8F, 0xFE            | SCANLINE 14
        .byte 0x77, 0x74, 0xCF, 0xFE            | SCANLINE 15
        .byte 0x54, 0x44, 0x87, 0xBC            | SCANLINE 16
        .byte 0x54, 0x47, 0xE3, 0x18            | SCANLINE 17
        .byte 0x00, 0x00, 0x00, 0x00            | SCANLINE 18
        .byte 0x77, 0x45, 0xD7, 0xFE            | SCANLINE 19
        .byte 0x45, 0x6D, 0x55, 0x4A            | SCANLINE 20
        .byte 0x45, 0x55, 0xD5, 0x6E            | SCANLINE 21
        .byte 0x45, 0x45, 0x15, 0x4C            | SCANLINE 22
        .byte 0x77, 0x45, 0x1D, 0x7A            | SCANLINE 23
        .byte 0x00, 0x00, 0x00, 0x00            | SCANLINE 24

| -----------------------------------------------------
| GET SOME BYTES AND QUIT
GETDONE:
        MOVE.L  A3,-(SP)                        | PUSH DATAPTR
        MOVE    D6,-(SP)                        | PUSH BYTECOUNT
        JSR     GetPicData(PC)                  | GET DATA FROM THEPIC
        BRA.W   KILL1_EXIT                      | GO TO COMMON SCALING

| ------------------------------------------------------
| LOCAL PROCEDURE TO GET AN UNSIGNED BYTE INTO D0 FROM PICTURE
| Called by: PicItem, GET2, TEXTOP, PICITEM_DHOK, TEXTOP2 (and 1 more) | jump via A0
GETUBYTE:                                       | jump via A0
        CLR.B   -(SP)                           | ALLOCATE TEMP
        MOVE.L  SP,-(SP)                        | PUSH ADDR OF TEMP
        MOVE    #0x1,-(SP)                      | PUSH BYTECOUNT
        JSR     GetPicData(PC)                  | GET DATA FROM THEPIC
        CLR     D0                              | GET READY FOR BYTE
        MOVE.B  (SP)+,D0                        | POP RESULT INTO LO BYTE
        RTS                                     | RETURN TO CALLER
GETSBYTE:
        CLR.B   -(SP)                           | ALLOCATE TEMP
        MOVE.L  SP,-(SP)                        | PUSH ADDR OF TEMP
        MOVE    #0x1,-(SP)                      | PUSH BYTECOUNT
        JSR     GetPicData(PC)                  | GET DATA FROM THEPIC
        MOVE.B  (SP)+,D0                        | POP RESULT
        EXT.W    D0                             | SIGN EXTEND TO WORD
        RTS                                     | RETURN TO CALLER
GETWORD:
        CLR     -(SP)                           | ALLOCATE TEMP
        MOVE.L  SP,-(SP)                        | PUSH ADDR OF TEMP
        MOVE    #0x2,-(SP)                      | PUSH BYTECOUNT
        JSR     GetPicData(PC)                  | GET DATA FROM THEPIC
        MOVE    (SP)+,D0                        | RETURN ANSWER IN D0
        RTS                                     | RETURN TO CALLER

| GETWORD_NO -- gET PNSIZE.
| ---------------------------------------------------------- 
| call subroutine via A0 | call subroutine via A0
| GETWORD_NO
GETWORD_NO:
        CLR.L   -(SP)                           | ALLOCATE TEMP
        MOVE.L  SP,-(SP)                        | PUSH ADDR OF TEMP
        MOVE    #0x4,-(SP)                      | PUSH UPDATERGN HANDLE
        JSR     GetPicData(PC)                  | pc-relative jsr (was raw .short pair)
        MOVE.L  (SP)+,D0                        | RETURN ANSWER IN D0
        RTS                                     | return to caller

| GETRECT -- gET AND PUSH DSTRECT.
| ----------------------------------------------------------
| GETRECT
GETRECT:
        TST.B   -0x28(A6)                       | SAME RECT ?
        BNE.B   SAME1                           | YES, CONTINUE
        MOVE.L  8(A6),A2                        | POINT TO PLAYSTATE RECORD
        PEA.L     (A2)                          | PUSH ADDR OF THERECT
        MOVE    #0x8,-(SP)                      | PUSH BYTECOUNT
        JSR     GetPicData(PC)                  | GET DATA FROM THEPIC
SAME1:
        MOVE.L  8(A6),A2                        | POINT TO PLAYSTATE RECORD
        MOVE.L  (A2),-16(A6)                    | COPY THERECT INTO DSTRECT
        MOVE.L  4(A2),-12(A6)                   | COPY THERECT INTO DSTRECT
        PEA.L     -16(A6)                       | PUSH LOCAL POINT
        PEA.L     20(A2)                        | PUSH SOURCE RECT
        PEA.L     28(A2)                        | PUSH DEST RECT
        JSR     MapRect(PC)                     | MAP DSTRECT
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        PEA.L     -16(A6)                       | PUSH ADDR OF MAPPED DSTRECT
        JMP     (A0)                            | RETURN
GETHNDL:
        MOVEQ.L #0x2,D4                         | jump via A0
        BSR.B   GETWORD                         | GET BYTECOUNT
GETHND2:
        MOVE    D0,D5                           | D5 := D0
        CLR.L   -(SP)                           | push zero word
        MOVE    D5,-(SP)                        | push D5
        JSR     NewHandle_Inline(PC)            | call NewHandle_Inline
        MOVE.L  (SP),-4(A6)                     | playState := (SP)
        JSR     HLock_Inline(PC)                | call HLock_Inline
        MOVE.L  -4(A6),A0                       | A0 := playState
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        MOVE    D5,(A0)                         | INSTALL SIZE WORD
        SUB     D4,D5                           | ADJUST COUNT
        PEA.L     0(A0,D4.W)                    | jump via A0
        MOVE    D5,-(SP)                        | PUSH BYTECOUNT
        JSR     GetPicData(PC)                  | call GetPicData
        MOVE.L  -4(A6),-(SP)                    | -(SP) := playState
        JSR     HUNLOCK_POP_RTS(PC)             | GET DATA FROM THEPIC
        RTS                                     | AND RETURN
CALL0:
        JSR     (A0)                            | call subroutine via A0
        BRA.B   KILL1_EXIT                      | AND QUIT
CALL1:
        JSR     (A0)                            | call subroutine via A0
        BRA.B   KILL1                           | jump via A0
KILL2:
        MOVE.L  -8(A6),-(SP)                    | -(SP) := tempHndl
        JSR     KillPicture(PC)                 | call KillPicture
KILL1:
        MOVE.L  -4(A6),-(SP)                    | -(SP) := playState
        JSR     KillPicture(PC)                 | call KillPicture
KILL1_EXIT:
        MOVEM.L (SP)+,D3-D7/A2-A4               | RESTORE REGISTERS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,(SP)                      | pop (SP)
        RTS                                     | return to caller
| Called by: TEXTOP2, PICITEM_MORE1, PICITEM_NOPACK, GETDONE, GETUBYTE (and 5 more)
GetPicData:
        MOVE.L  (A5),A0                         | A0 := (A5)
        MOVE.L  (A0),A0                         | A0 := (A0)
        MOVE.L  0x68(A0),D0                     | D0 := 0x68(A0)
        BNE.B   GETPICDATA_EMPTY                | if non-zero -> GETPICDATA_EMPTY
        JMP     StdGetPic(PC)                   | YES, USE STD PROC
GETPICDATA_EMPTY:
        MOVE.L  D0,A0                           | A0 := D0
        MOVE.L  0x2C(A0),A0                     | A0 := 0x2C(A0)
        JMP     (A0)                            | RTS
| Called by: NOPACK, TEXT2, NOPACK_PACK_LOOP, NOPACK_NOPACK_LOOP, STDCOMMENT_CONT (and 6 more)
PutPicData:
        MOVE.L  (A5),A0                         | A0 := (A5)
        MOVE.L  (A0),A0                         | A0 := (A0)
        MOVE.L  0x68(A0),D0                     | D0 := 0x68(A0)
        BNE.B   PUTPICDATA_EMPTY                | if non-zero -> PUTPICDATA_EMPTY
        JMP     StdPutPic(PC)                   | YES, USE STD PROC
PUTPICDATA_EMPTY:
        MOVE.L  D0,A0                           | A0 := D0
        MOVE.L  0x30(A0),A0                     | A0 := 0x30(A0)
        JMP     (A0)                            | RTS

| .PROC DPutPicByte,1
| .DEF PutPicByte
| .REF PutPicData
| ------------------------------------------------------
| PROCEDURE PutPicByte(data: Byte);
| Called by: FONTOK, STDTEXT_DHDV, DHDV, StdText, FACEOK (and 28 more)
PutPicByte:
        PEA.L     4(SP)                         | PUSH ADDR OF DATA
        MOVE    #0x1,-(SP)                      | PUSH BYTECOUNT = 1
        JSR     PutPicData(PC)                  | CALL PutPicData
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        TST.B   (SP)+                           | STRIP PARAM
        JMP     (A0)                            | AND RETURN

| PutPicWord -- pUT KIND.
| ----------------------------------------------------------
| Put Pic Word
| Called by: StdArc, STDCOMMENT_CONT, StdText, FACEOK, STDTEXT_MODEOK (and 4 more)
PutPicWord:
        PEA.L     4(SP)                         | PUSH ADDR OF DATA
        MOVE    #0x2,-(SP)                      | PUSH BYTECOUNT = 2
        JSR     PutPicData(PC)                  | CALL PutPicData
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        TST     (SP)+                           | STRIP PARAM
        JMP     (A0)                            | AND RETURN

| PutPicLong -- yES, PUT STARTPT = PNLOC.
| ----------------------------------------------------------
| Put Pic Long
| Called by: STDTEXT_NOTSAME, STDTEXT_SIZEOK, STDTEXT_NOTSAME_NO, PUTOP, STDLINE_STARTOK (and 5 more)
PutPicLong:
        PEA.L     4(SP)                         | PUSH ADDR OF DATA
        MOVE    #0x4,-(SP)                      | PUSH BYTECOUNT = 4
        JSR     PutPicData(PC)                  | CALL PutPicData
        MOVE.L  (SP)+,(SP)                      | STRIP PARAM
        RTS                                     | RETURN TO CALLER

| PutPicPat -- pUT PATTERN DATA.
| ----------------------------------------------------------
| Put Pic Pat
PutPicPat:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE    #0x8,-(SP)                      | PUSH BYTECOUNT = 8
        MOVE.L  A0,-(SP)                        | PUSH RETURN ADDR
        JMP     PutPicData(PC)                  | SAVE PICTURE DATA

| PutPicRect -- pUT OPCODE AND RECTANGLE.
| ----------------------------------------------------------
| Put Pic Rect
PutPicRect:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF RECT
        MOVE.B  (SP)+,D2                        | pop D2
        MOVE.L  A0,-(SP)                        | PUSH RETURN ADDR
        MOVE.L  (A1),D0                         | D0 := (A1)
        MOVE.L  4(A1),D1                        | GET BOTRIGHT
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE.L  0x5C(A0),A0                     | GET PICSAVE HANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE PICSAVE
        CMP.L   0x44(A0),D0                     | compare D0 with 0x44(A0)
        BNE.B   NOTSAME                         | NO, CONTINUE
        CMP.L   0x48(A0),D1                     | IS BOTRIGHT THE SAME ?
        BNE.B   NOTSAME                         | NO, CONTINUE
        ADDQ.W  #0x8,D2                         | D2 += #0x8
        MOVE.B  D2,-(SP)                        | push D2
        JSR     PutPicByte(PC)                  | emit byte into picture stream
        RTS                                     | return to caller
NOTSAME:
        MOVE.L  D0,0x44(A0)                     | 0x44(A0) := D0
        MOVE.L  D1,0x48(A0)                     | 0x48(A0) := D1
        MOVE.L  A1,-(SP)                        | PUSH ADDR OF RECT FOR BELOW
        MOVE    #0x8,-(SP)                      | push #0x8
        MOVE.B  D2,-(SP)                        | push D2
        JSR     PutPicByte(PC)                  | PUT OPCODE (IN D0)
        JSR     PutPicData(PC)                  | PUT 8 BYTES OF RECTANGLE
        RTS                                     | return to caller
PutPicRgn:
        MOVE.L  4(SP),-(SP)                     | push 4(SP)
        JSR     HLock_Inline(PC)                | call HLock_Inline
        MOVE.L  4(SP),A0                        | GET HANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        MOVE.L  A0,-(SP)                        | PUSH DATAPTR
        MOVE    (A0),-(SP)                      | PUSH BYTECOUNT
        JSR     PutPicData(PC)                  | emit raw data into picture stream
        MOVE.L  4(SP),-(SP)                     | push 4(SP)
        JSR     HUNLOCK_POP_RTS(PC)             | ADD TO THEPIC
        MOVE.L  (SP)+,(SP)                      | STRIP PARAM
        RTS                                     | AND RETURN

| PutPicVerb -- pUT ADDIONAL PARAMS TO THEPIC.
| ----------------------------------------------------------
| Put Pic Verb
| Called by: StdLine, StdRect, StdRRect, StdOval, StdArc (and 2 more)
PutPicVerb:
        LINK    A6,#0x0                         | NO LOCAL VARS
        MOVEM.L D5-D7/A3-A4,-(SP)               | SAVE REGS
        MOVE.L  (A5),A4                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A4),A3                         | GET CURRENT GRAFPORT
        MOVE.L  0x5C(A3),A4                     | GET PICSAVE HANDLE
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE
        MOVE.B  8(A6),D7                        | GET VERB
        CMPI.B  #0x1,D7                         | CASE JUMP BASSED ON VERB
        BLT.B   FRAME1                          | if signed < -> FRAME1
        BEQ.W   PAINT1                          | YES CHECK PNMODE, PNPAT
        CMPI.B  #0x3,D7                         | IS VERB INVERT ?
        BEQ.W   PAINT1_EXIT                     | YES, NOTHING TO CHECK
        BLT.B   ERASE1                          | if signed < -> ERASE1
        MOVE.L  0x28(A3),D5                     | FILL1: GET FILLPAT
        MOVE.L  0x2C(A3),D6                     | GET FILLPAT
        CMP.L   0x3C(A4),D5                     | SAME AS PICFILLPAT ?
        BNE.B   PUTPICVERB_NO                   | NO, PUT CHANGE TO THEPIC
        CMP.L   0x40(A4),D6                     | COMPARE WITH SAVED PATTERN
        BEQ.W   PAINT1_EXIT                     | if zero -> PAINT1_EXIT
PUTPICVERB_NO:
        MOVE.L  D5,0x3C(A4)                     | 0x3C(A4) := D5
        MOVE.L  D6,0x40(A4)                     | 0x40(A4) := D6
        MOVE.B  #0xA,-(SP)                      | push #0xA
        JSR     PutPicByte(PC)                  | ADD TO THEPIC
        PEA.L     0x28(A3)                      | push &thePort.fillPat
        JSR     PutPicPat(PC)                   | PUT PATTERN DATA
        BRA.W   PAINT1_EXIT                     | AND QUIT
ERASE1:
        MOVE.L  0x20(A3),D5                     | jump via A0
        MOVE.L  0x24(A3),D6                     | D6 := 0x24(A3)
        CMP.L   10(A4),D5                       | SAME AS PICBKPAT ?
        BNE.B   NEWBK                           | NO, PUT CHANGE TO THEPIC
        CMP.L   14(A4),D6                       | compare D6 with 14(A4)
        BEQ.W   PAINT1_EXIT                     | if zero -> PAINT1_EXIT
NEWBK:
        MOVE.L  D5,10(A4)                       | UPDATE STATE VARIABLE
        MOVE.L  D6,14(A4)                       | 14(A4) := D6
        MOVE.B  #0x2,-(SP)                      | push #0x2
        JSR     PutPicByte(PC)                  | ADD TO THEPIC
        PEA.L     0x20(A3)                      | push &thePort.bkPat
        JSR     PutPicPat(PC)                   | PUT PATTERN DATA
        BRA.B   PAINT1_EXIT                     | AND QUIT
FRAME1:
        MOVE.L  0x34(A3),D6                     | D6 := thePort.pnSize
        CMP.L   0x2E(A4),D6                     | compare D6 with 0x2E(A4)
        BEQ.B   PAINT1                          | NO, CONTINUE
        MOVE.B  #0x7,-(SP)                      | push #0x7
        JSR     PutPicByte(PC)                  | YES, PUT PNSIZE OPCODE
        MOVE.L  D6,-(SP)                        | push D6
        JSR     PutPicLong(PC)                  | PUT NEW PNSIZE
        MOVE.L  0x5C(A3),A4                     | A4 := thePort.picSave
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE
        MOVE.L  D6,0x2E(A4)                     | 0x2E(A4) := D6
PAINT1:
        MOVE    0x38(A3),D6                     | D6 := thePort.pnMode
        CMP     0x32(A4),D6                     | compare D6 with 0x32(A4)
        BEQ.B   PAINT1_NO                       | NO, CONTINUE
        MOVE.B  #0x8,-(SP)                      | push #0x8
        JSR     PutPicByte(PC)                  | YES, PUT PNMODE OPCODE
        MOVE    D6,-(SP)                        | push D6
        JSR     PutPicWord(PC)                  | PUT NEW PNMODE
        MOVE.L  0x5C(A3),A4                     | A4 := thePort.picSave
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE
        MOVE    D6,0x32(A4)                     | 0x32(A4) := D6
PAINT1_NO:
        MOVE.L  0x3A(A3),D5                     | D5 := thePort.pnPat
        MOVE.L  0x3E(A3),D6                     | D6 := 0x3E(A3)
        CMP.L   0x34(A4),D5                     | compare D5 with 0x34(A4)
        BNE.B   PAINT1_NO_2                     | if non-zero -> PAINT1_NO_2
        CMP.L   0x38(A4),D6                     | compare D6 with 0x38(A4)
        BEQ.B   PAINT1_EXIT                     | if zero -> PAINT1_EXIT
PAINT1_NO_2:
        MOVE.L  D5,0x34(A4)                     | 0x34(A4) := D5
        MOVE.L  D6,0x38(A4)                     | 0x38(A4) := D6
        MOVE.B  #0x9,-(SP)                      | push #0x9
        JSR     PutPicByte(PC)                  | ADD TO THEPIC
        PEA.L     0x3A(A3)                      | push &thePort.pnPat
        JSR     PutPicPat(PC)                   | PUT PATTERN DATA
PAINT1_EXIT:
        MOVEM.L (SP)+,D5-D7/A3-A4               | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address into A0
        ADDQ.W  #0x2,SP                         | pop parameter bytes from stack
        JMP     (A0)                            | RTS
| Called by: StdText, StdLine, StdRect, StdRRect, StdOval (and 4 more)
CheckPic:
        MOVEM.L D7,-(SP)                        | save scratch regs to stack
        MOVE.L  (A5),A4                         | A4 := (A5)
        MOVE.L  (A4),A3                         | A3 := (A4)
        TST.L   0x5C(A3)                        | test 0x5C(A3)
        BEQ.W   ORIGNOK_EXIT_2                  | NO, QUIT
        CMPI    #-0x1,0x42(A3)                  | compare 0x42(A3) with #-0x1
        BLT.W   ORIGNOK_EXIT_2                  | YES, DON'T ADD TO THEPIC
        MOVE.L  0x5C(A3),A4                     | A4 := thePort.picSave
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE
        MOVE.L  0x50(A3),D7                     | D7 := thePort.fgColor
        CMP.L   0x54(A4),D7                     | compare D7 with 0x54(A4)
        BEQ.B   CHECKPIC_NO                     | NO, CONTINUE
        MOVE.B  #0xE,-(SP)                      | push #0xE
        JSR     PutPicByte(PC)                  | PUT FGCOLOR OPCODE
        MOVE.L  D7,-(SP)                        | push D7
        JSR     PutPicLong(PC)                  | PUT FGCOLOR
        MOVE.L  0x5C(A3),A4                     | A4 := thePort.picSave
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE
        MOVE.L  D7,0x54(A4)                     | 0x54(A4) := D7
CHECKPIC_NO:
        MOVE.L  0x54(A3),D7                     | D7 := thePort.bkColor
        CMP.L   0x58(A4),D7                     | compare D7 with 0x58(A4)
        BEQ.B   CHECKPIC_NO_2                   | NO, CONTINUE
        MOVE.B  #0xF,-(SP)                      | push #0xF
        JSR     PutPicByte(PC)                  | PUT BKCOLOR OPCODE
        MOVE.L  D7,-(SP)                        | push D7
        JSR     PutPicLong(PC)                  | PUT BKCOLOR PARAM
        MOVE.L  0x5C(A3),A4                     | A4 := thePort.picSave
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE
        MOVE.L  D7,0x58(A4)                     | 0x58(A4) := D7
CHECKPIC_NO_2:
        MOVE.L  16(A3),D0                       | D0 := thePort.portRect
        CMP.L   0x50(A4),D0                     | compare D0 with 0x50(A4)
        BEQ.B   ORIGNOK                         | YES, CONTINUE
        MOVE    18(A3),D7                       | D7 := 18(A3)
        SUB     0x52(A4),D7                     | D7 -= 0x52(A4)
        ADD     D7,0x52(A4)                     | 0x52(A4) += D7
        SWAP    D7                              | PUT DH IN HI WORD
        MOVE    16(A3),D7                       | D7 := thePort.portRect
        SUB     0x50(A4),D7                     | D7 -= 0x50(A4)
        ADD     D7,0x50(A4)                     | 0x50(A4) += D7
        MOVE.B  #0xC,-(SP)                      | push #0xC
        JSR     PutPicByte(PC)                  | jump via A0
        MOVE.L  D7,-(SP)                        | push D7
        JSR     PutPicLong(PC)                  | PUT DH,DV TO THEPIC
        MOVE.L  0x5C(A3),A4                     | A4 := thePort.picSave
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE
ORIGNOK:
        CLR.B   -(SP)                           | MAKE ROOM FOR FCN VALUE
        MOVE.L  28(A3),-(SP)                    | PUSH CLIPRGN
        MOVE.L  6(A4),-(SP)                     | PUSH STATE VARIABLE
        JSR     EqualRgn(PC)                    | ARE THEY THE SAME ?
        TST.B   (SP)+                           | TEST RESULT
        BNE.B   CLIPOK                          | QUIT IF SAME
        MOVE.L  28(A3),-(SP)                    | SET UP FOR COPYRGN BELOW
        MOVE.L  6(A4),-(SP)                     | push 6(A4)
        MOVE.B  #0x1,-(SP)                      | push #0x1
        JSR     PutPicByte(PC)                  | PUT CLIPRGN PARAM OPCODE
        MOVE.L  28(A3),-(SP)                    | PUSH CLIPRGN HANDLE
        JSR     PutPicRgn(PC)                   | PUT CLIPRGN TO THEPIC
        JSR     CopyRgn(PC)                     | COPY CLIPRGN INTO PICCLIPRGN
CLIPOK:
        MOVE.L  (A5),A4                         | A4 := (A5)
        MOVEQ.L #0x1,D0                         | D0 := #0x1
ORIGNOK_EXIT_2:
        MOVEM.L (SP)+,D7                        | MOVEM FOR CC, RESTORE REGS
        RTS                                     | AND RETURN

| .PROC ScalePt
| -------------------------------------------------------------
| PROCEDURE ScalePt(VAR pt: Point; fromRect,toRect: Rect);
| Scale a width and height from one coordinate system to another.
| If fromRect and toRect are the same size, then no change.
| If the input > 0, then enforce 1 pixel minimum on the output.
| pt.h := (pt.h * fromWidth) / toWidth
| pt.v := (pt.v * fromHeight) / toHeight
| restores ALL registers.
| A6 OFFSETS OF PARAMS AFTER LINK:
| PARAMSIZE .EQU 12 ;TOTAL BYTES OF PARAMS
| PT .EQU PARAMSIZE+8-4 ;LONG, ADDR OF POINT
| FROMRECT .EQU PT-4 ;LONG, ADDR OF RECT
| TORECT .EQU FROMRECT-4 ;LONG, ADDR OF RECT
ScalePt:
        LINK    A6,#0x0                         | NO LOCALS
        MOVEM.L D0-D6/A0-A2,-(SP)               | SAVE REGS
        MOVE.L  16(A6),A0                       | POINT TO VAR PT
        MOVE.L  12(A6),A1                       | POINT TO FROMRECT
        MOVE.L  8(A6),A2                        | POINT TO TORECT
        BSR.B   SCALEPT_CONT                    | SCALE THE HEIGHT
        ADDQ.W  #0x2,A0                         | OFFSET TO PT.H
        ADDQ.W  #0x2,A1                         | OFFSET TO FROMRECT.H
        ADDQ.W  #0x2,A2                         | OFFSET TO TORECT.H
        BSR.B   SCALEPT_CONT                    | SCALE THE WIDTH
        MOVEM.L (SP)+,D0-D6/A0-A2               | DONE: RESTORE REGS
        UNLK    A6                              | RESTORE STACK FRAME
        MOVE.L  (SP)+,A0                        | GET RETURN ADDRESS
        ADDA.W  #0xC,SP                         | POP PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER

| SCALEPT_CONT -- sCALE THE HEIGHT.
| ----------------------------------------------------------
| SCALEPT_CONT
SCALEPT_CONT:
        MOVE    4(A1),D3                        | GET FROMRECT BOTTOM
        SUB     (A1),D3                         | D3 -= (A1)
        MOVE    4(A2),D2                        | GET TORECT BOTTOM
        SUB     (A2),D2                         | D2 -= (A2)
        CMP     D2,D3                           | ARE BOTH HEIGHTS THE SAME ?
        BEQ.B   SCDONE                          | YES, SKIP
        MOVE    D3,D1                           | COPY DENOM = FROMHEIGHT
        LSR     #0x1,D1                         | D1 >>= 1 (logical)
        EXT.L    D1                             | MAKE IT LONG
        MOVE    (A0),D0                         | GET SIZE COORD
        BGT.B   POS                             | CONTINUE IF POSITIVE
        CLR     (A0)                            | ELSE SET IT TO ZERO
        RTS                                     | AND QUIT
POS:
        MULU    D2,D0                           | MULT BY TORECT HEIGHT
        ADD.L   D1,D0                           | ADD FROMHEIGHT/2 FOR ROUNDING
        DIVU    D3,D0                           | DIV BY FROMHEIGHT
        BNE.B   MINSIZE_EMPTY                   | IS RESULT ZERO ?
        MOVEQ.L #0x1,D0                         | D0 := #0x1
MINSIZE_EMPTY:
        MOVE    D0,(A0)                         | UPDATE RESULT
SCDONE:
        RTS                                     | return to caller
| Called by: MapRect, MAPPOLY_NEXTPT, MAPRGN_LOOP, LNFROM, LNOK (and 1 more)
MapPt:
        LINK    A6,#0x0                         | set up stack frame, reserve 0x0 locals
        MOVEM.L D0-D6/A0-A2,-(SP)               | SAVE REGS
        MOVE.L  16(A6),A0                       | PUSH TORECT
        MOVE.L  12(A6),A1                       | POINT TO FROMRECT
        MOVE.L  8(A6),A2                        | POINT TO TORECT
        BSR.B   MAP1                            | MAP THE VERTICAL COORD
        ADDQ.W  #0x2,A0                         | A0 += #0x2
        ADDQ.W  #0x2,A1                         | A1 += #0x2
        ADDQ.W  #0x2,A2                         | A2 += #0x2
        BSR.B   MAP1                            | MAP THE HORIZ COORD
        MOVEM.L (SP)+,D0-D6/A0-A2               | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address into A0
        ADDA.W  #0xC,SP                         | pop parameter bytes from stack
        JMP     (A0)                            | RTS
| jump via A1 | jump via A1
| MAP1 -- mAP THE VERTICAL COORD.
| ----------------------------------------------------------
| MAP1
MAP1:
        MOVE    (A1),D2                         | GET DATA
        MOVE    4(A1),D3                        | GET FROMRECT BOTTOM
        SUB     D2,D3                           | CALC FROMHEIGHT
        MOVE    (A2),D4                         | GET TORECT TOP
        MOVE    4(A2),D5                        | GET TORECT BOTTOM
        SUB     D4,D5                           | CALC TORECT HEIGHT
        MOVE    (A0),D0                         | GET COORD
        SUB     D2,D0                           | SUBTRACT FROMRECT TOP
        CMP     D3,D5                           | ARE BOTH HEIGHTS SAME ?
        BEQ.B   NOTNEG_SKIP                     | YES, SKIP THE SCALING
        MOVE    D3,D1                           | DENOM = FROMHEIGHT
        LSR     #0x1,D1                         | CALC DENOM/2 (DENOM ALWAYS POS)
        EXT.L    D1                             | MAKE DENOM/2 LONG
        MOVE    D0,D2                           | IS COORD NEGATIVE ?
        BPL.B   NOTNEG                          | NO, CONTINUE
        NEG     D0                              | YES, MAKE IT POSITIVE FOR MULDIV
NOTNEG:
        MULU    D5,D0                           | MULT COORD BY TORECT HEIGHT
        ADD.L   D1,D0                           | ADD FROMHEIGHT/2 FOR ROUNDING
        DIVU    D3,D0                           | DIV BY FROMHEIGHT
        TST     D2                              | WAS OLD COORD NEG ?
        BPL.B   NOTNEG_SKIP                     | NO, CONTINUE
        NEG     D0                              | YES, RESTORE IT TO NEGATIVE
NOTNEG_SKIP:
        ADD.W    D4,D0                          | D0 += D4
        MOVE.W   D0,(A0)                        | (A0) := D0
        RTS                                     | return to caller

| .PROC MapRect,3
| .REF MapPt
| -------------------------------------------------------------
| PROCEDURE MapRect(VAR dstRect: Rect; fromRect,toRect: Rect);
| Map both points of a rectangle from one coordinate system to another.
| restores ALL registers.
| Called by: DrText, DOWN2, MAPPOLY_CONT, MAPRGN_NO, TEXTOP2 (and 1 more)
MapRect:
        MOVE.L  12(SP),-(SP)                    | PUSH DSTRECT
        MOVE.L  12(SP),-(SP)                    | PUSH FROMRECT
        MOVE.L  12(SP),-(SP)                    | PUSH TORECT
        JSR     MapPt(PC)                       | MAP TOPLEFT POINT
        ADDQ.L  #0x4,12(SP)                     | OFFSET RECT TO BOTRIGHT
        JMP     MapPt(PC)                       | MAP BOTRIGHT AND RETURN

| NewHandle_Inline -- aLLOCATE PTBUF.
| Called by: OpenPicture, OpenPoly, NewRgn, OpenRgn, INSETRGN_NOTRECT (and 4 more)
NewHandle_Inline:
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE.L  (SP)+,A1                        | pop return jump address
        MOVE    (SP)+,D0                        | pop requested size into D0
        _NewHandle                              | allocate handle of size D0
        BNE.B   MEMFULL_SYSERR                  | if non-zero -> MEMFULL_SYSERR
        MOVE.L  A0,(SP)                         | (SP) := A0
        JMP     (A1)                            | jump via A1
MEMFULL_SYSERR:
        MOVEQ.L #0x19,D0                        | D0 = dsMemFullErr (25)
        _SysError                               | system error (halt)
        _Debugger                               | (unreachable) drop to debugger

| SetHSize -- mAKE THE BUFFER BIGGER.
| Called by: DOLINE_CONT, DVPOS_OK, PutRect, PUTPT, EMPTY (and 9 more)
SetHSize:
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE.L  (SP)+,A1                        | pop return jump address
        MOVE    (SP)+,D0                        | pop new size into D0
        MOVE.L  (SP)+,A0                        | pop handle into A0
        _SetHandleSize                          | resize handle A0 to D0 bytes
        BNE.B   MEMFULL_SYSERR                  | if non-zero -> MEMFULL_SYSERR
        JMP     (A1)                            | jump via A1
| RTS ;AND RETURN
| .PROC KillPicture
| ---------------------------------------------------
| PROCEDURE KillPicture(myPicture: PicHandle);
| Called by: NEWRGN_CONT, CloseRgn, INSETRGN_FINISH, JDONE_NO_2, MAPRGN_LOOP_2 (and 4 more)
KillPicture:
        MOVE.L  (SP)+,A1                        | pop return addr
        MOVE.L  (SP)+,A0                        | pop handle
        _DisposeHandle                          | DISCARD PICHANDLE
        JMP     (A1)                            | and return
