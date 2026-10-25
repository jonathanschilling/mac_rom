| -----------------------------------------------------------
|
|
|     ****   ***  *****  *     *     *     ****    ***
|     *   *   *     *    **   **    * *    *   *  *   *
|     *   *   *     *    * * * *   *   *   *   *  *
|     ****    *     *    *  *  *   *   *   ****    ***
|     *   *   *     *    *     *   *****   *          *
|     *   *   *     *    *     *   *   *   *      *   *
|     ****   ***    *    *     *   *   *   *       ***
|
|
|
|  QuickDraw Routines to operate on BitMaps.
|

| .PROC StdBits,5
| .REF CheckPic,PutPicByte,PutPicWord,PutPicRgn,PutPicData
| .REF StretchBits,PackBits
| ---------------------------------------------------------------
|
| PROCEDURE StdBits(VAR srcBits: BitMap;
| VAR srcRect: Rect;
| VAR dstRect: Rect;
| mode: INTEGER;
| maskRgn: RgnHandle);
|
| A6 OFFSETS OF PARAMS AFTER LINK:
|
| Called during boot.
|
StdBits:
        LINK    A6,#-0x116                      | set up stack frame
        MOVEM.L D3-D7/A2-A4,-(SP)               | SAVE REGS
        JSR     CheckPic(PC)                    | SET UP A4,A3 AND CHECK PICSAVE
        BLE.W   STDBITS_NOTPIC                  | BRANCH IF NOT PICSAVE
        MOVE.L  22(A6),A0                       | GET ADDR OF SRCBITS
        LEA.L     -14(A6),A1                    | A1 := MYBITS local copy
        MOVE.L  (A0),A3                         | A3 := SRCBITS.BASEADDR
        MOVE    4(A0),D4                        | GET OLD ROWBYTES
        MOVE.L  6(A0),6(A1)                     | COPY BOUNDS TOPLEFT
        MOVE.L  10(A0),10(A1)                   | COPY BOUNDS BOTRIGHT
        MOVE.L  18(A6),A0                       | POINT TO SRCRECT
        MOVE    (A0),D0                         | GET SRCRECT.TOP
        SUB     6(A1),D0                        | SKIPTOP := top - bounds.top
        BLE.B   NXTHOR_CONT_3                   | CONTINUE IF SKIPTOP NEG
        ADD     D0,6(A1)                        | 6(A1) += D0
        MULU    D4,D0                           | CALC VERT OFFSET
        ADDA.L  D0,A3                           | ADJUST BASEADDR
NXTHOR_CONT_3:
        MOVE    4(A0),D0                        | GET SRCRECT.BOTTOM
        CMP     10(A1),D0                       | IS SRCRECT BOT < BOUNDS BOT ?
        BGE.B   BOTOK                           | NO, CONTINUE
        MOVE    D0,10(A1)                       | YES, TRIM BOUNDS BOTTOM
BOTOK:
        MOVE    2(A0),D0                        | GET SRCRECT.LEFT
        SUB     8(A1),D0                        | CALC SKIPLEFT
        BLE.B   LEFTOK                          | CONTINUE IF SKIPLEFT NEG
        LSR     #0x3,D0                         | DIV BY 8 FOR SKIP BYTES
        ADDA.W  D0,A3                           | OFFSET BASEADDR HORIZ
        LSL     #0x3,D0                         | BYTES TIMES 8 FOR DOTS
        ADD     D0,8(A1)                        | ADJUST BOUNDS.LEFT
LEFTOK:
        MOVE    6(A0),D0                        | GET SRCRECT.RIGHT
        SUB     8(A1),D0                        | CALC DELTA RIGHT
        ADDQ.W  #0x7,D0                         | ROUND UP TO BYTE
        LSR     #0x3,D0                         | TO NEXT MULT OF 8
        LSL     #0x3,D0                         | CONVERT BACK TO DOTS
        ADD     8(A1),D0                        | ADD BOUNDS.LEFT BACK
        CMP     12(A1),D0                       | IS NEW RIGHT < BOUNDS.RIGHT ?
        BGE.B   LEFTOK_NORECT                   | NO, CONTINUE
        MOVE    D0,12(A1)                       | YES, TRIM BOUNDS.RIGHT
LEFTOK_NORECT:
        MOVE    12(A1),D5                       | GET TRIMMED RIGHT
        SUB     8(A1),D5                        | CALC WIDTH IN DOTS
        ADDI    #0xF,D5                         | ROUND UP TO WORD
        LSR     #0x4,D5                         | DIV BY 16
        BLE.W   NOPACK_EXIT                     | IGNORE IF NEWROW <= 0
        ADD     D5,D5                           | DOUBLE FOR NEW ROWBYTES
        MOVE    D5,0x4(A1)                      | COPY ROWBYTES
        MOVE.B  #0x90,-(SP)                     | push packtype default 0x90
        TST.L   0x8(A6)                         | test picture handle
        BEQ.B   LEFTOK_NORECT_NOPIC             | no handle -> skip update
        MOVE.B  #0x90,(SP)                      | overwrite packtype
LEFTOK_NORECT_NOPIC:
        CMPI    #0x8,D5                         | rowbytes >= 8?
        BLT.B   NOPACK                          | YES, DONT BITPACK
        ADDQ.B  #0x8,(SP)                       | (SP) += 0x8
NOPACK:
        JSR     PutPicByte(PC)                  | PUT OPCODE TO THEPIC
        PEA.L     -10(A6)                       | PUSH ADDR OF MYBITS+ROWBYTES
        MOVE    #0xA,-(SP)                      | PUSH BYTECOUNT = 10
        JSR     PutPicData(PC)                  | PUT ROWBYTES,BOUNDS TO THEPIC
        MOVE.L  18(A6),-(SP)                    | PUSH SRCRECT ADDR
        MOVE    #0x8,-(SP)                      | push 8-byte rect size
        JSR     PutPicData(PC)                  | PUT SRCRECT
        MOVE.L  14(A6),-(SP)                    | push DSTRECT addr
        MOVE    #0x8,-(SP)                      | push 8-byte rect size
        JSR     PutPicData(PC)                  | PUT DSTRECT
        MOVE    12(A6),-(SP)                    | push MODE
        JSR     PutPicWord(PC)                  | PUT MODE
        TST.L   8(A6)                           | IS MASKRGN NIL ?
        BEQ.B   NOPACK_SETUP                    | YES, SKIP IT
        MOVE.L  8(A6),-(SP)                     | NO, PUSH MASKRGN
        JSR     PutPicRgn(PC)                   | PUT MASKRGN TO THEPIC
NOPACK_SETUP:
        LEA.L     -14(A6),A2                    | jump via A0
        MOVE    10(A2),D7                       | get bounds.bottom
        SUB     6(A2),D7                        | HEIGHT := bot - top
        CMPI    #0x8,D5                         | IS NEWROW < 8 ?
        BLT.B   STDBITS_RAWROW_TEST             | YES, DONT TRY TO PACK
        BRA.B   STDBITS_PACKROW_TEST            | GO TO LOOP START
NOPACK_PACK_LOOP:
        MOVE.L  A3,-0x112(A6)                   | SRCPTR := ^SCANLINE DATA
        LEA.L     -0x10E(A6),A0                 | POINT TO PACKBUF
        MOVE.L  A0,-0x116(A6)                   | DSTPTR := @PACKBUF
        PEA.L     -0x112(A6)                    | PUSH VAR SRCPTR
        PEA.L     -0x116(A6)                    | PUSH VAR DSTPTR
        MOVE    D5,-(SP)                        | PUSH SRCBYTES = NEWROW
        JSR     PackBits(PC)                    | PACK ROW INTO PACKBUF
        MOVE.L  -0x116(A6),D6                   | GET UPDATED DSTPTR
        LEA.L     -0x10E(A6),A0                 | POINT TO PACKBUF
        SUB.L   A0,D6                           | CALC PACKED BYTECOUNT
        MOVE.B  D6,-(SP)                        | PUSH PACKED BYTECOUNT
        JSR     PutPicByte(PC)                  | PUT PACKED BYTECOUNT TO THEPIC
        PEA.L     -0x10E(A6)                    | PUSH PACKBUF ADDR
        MOVE    D6,-(SP)                        | PUSH PACKED SIZE
        JSR     PutPicData(PC)                  | PUT PACKED DATA TO THEPIC
        ADDA.W  D4,A3                           | ADD OLDROW TO BITS PTR
STDBITS_PACKROW_TEST:
        DBF     D7,NOPACK_PACK_LOOP             | decrement row count, loop
        BRA.B   NOPACK_EXIT                     | done with all rows
NOPACK_NOPACK_LOOP:
        MOVE.L  A3,-(SP)                        | PUSH ADDR OF BITS
        MOVE    D5,-(SP)                        | PUSH BYTECOUNT = NEWROW
        JSR     PutPicData(PC)                  | PUT ONE ROW OF BITMAP DATA
        ADDA.W  D4,A3                           | ADD OLDROW TO BITS PTR
STDBITS_RAWROW_TEST:
        DBF     D7,NOPACK_NOPACK_LOOP           | decrement row count, loop
NOPACK_EXIT:                                    | @ $9B64 (BRA.B target)
        MOVEA.L (A4),A3                         | restore A3 to port bitmap
STDBITS_NOTPIC:
        TST     0x42(A3)                        | NOTPIC: IS PNVIS >= 0 ?
        BLT.B   STDBITS_NOTPIC_EXIT             | NO, QUIT
        MOVE.L  22(A6),-(SP)                    | PUSH SRCBITS
        PEA.L     2(A3)                         | PUSH DSTBITS = PORTBITS
        MOVE.L  18(A6),-(SP)                    | PUSH SRCRECT
        MOVE.L  14(A6),-(SP)                    | PUSH DSTRECT
        MOVE    12(A6),-(SP)                    | PUSH MODE
        MOVE.L  28(A3),-(SP)                    | PUSH CLIPRGN
        MOVE.L  24(A3),-(SP)                    | PUSH VISRGN
        MOVE.L  8(A6),-(SP)                     | PUSH MASKRGN
        BNE.B   STDBITS_NOTPIC_EMPTY            | WAS IT NIL ?
        MOVE.L  -0x82(A4),(SP)                  | YES, REPLACE WITH WIDEOPEN
STDBITS_NOTPIC_EMPTY:
        JSR     StretchBits(PC)                 | CALL STRETCHBITS
STDBITS_NOTPIC_EXIT:
        MOVEM.L (SP)+,D3-D7/A2-A4               | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return PC
        ADDA.W  #0x12,SP                        | strip PARAMSIZE bytes
        JMP     (A0)                            | RTS
| ----------------------------------------------------------
|
| _CopyBits ($A8EC): copy a bit image from one bitmap to another
| Pascal: PROCEDURE CopyBits(srcBits, dstBits: BitMap; srcRect, dstRect: Rect;
|                            mode: INTEGER; maskRgn: RgnHandle);
| Shields the cursor if srcBits.baseAddr is the screen. If dstBits has
| thePort's portBits baseAddr and bounds.topLeft, calls the port's bitsProc
| (StdBits if grafProcs is nil); otherwise calls StretchBits directly with
| wideOpen for visRgn/clipRgn and for a nil maskRgn. Unlike the 1983
| Bitmaps.a, there is no check for a nil or odd thePort.
|
CopyBits:
        LINK    A6,#0x0                         | NO LOCAL VARS
        MOVEM.L D6-D7/A2-A4,-(SP)               | SAVE REGS
        MOVE.L  (A5),A4                         | POINT TO QD GLOBALS
        MOVE.L  (A4),A3                         | GET THEPORT
        MOVE.L  26(A6),A2                       | POINT TO SRCBITS
        MOVE.L  (A2),D7                         | GET SRC BASEADDR
        MOVE.L  -0x7A(A4),D6                    | GET SCREEN BASEADDR
        CMP.L   D6,D7                           | IS SRC FROM THE SCREEN ?
        BNE.B   STDBITS_NOTPIC_NO               | NO, CONTINUE
        MOVE.L  18(A6),-(SP)                    | YES, PUSH SRCRECT
        MOVE.L  6(A2),-(SP)                     | PUSH SRCBITS.BOUNDS.TOPLEFT
        JSR     ShieldCursor(PC)                | HIDE THE CURSOR IF IN SRCRECT
STDBITS_NOTPIC_NO:
        MOVE.L  22(A6),A1                       | POINT TO DSTBITS
        MOVE.L  2(A3),D0                        | GET PORTBITS.BASEADDR
        CMP.L   (A1),D0                         | IS DST BASEADDR SAME ?
        BNE.B   NOTPORT                         | NO, NOT TO THEPORT
        MOVE.L  8(A3),D0                        | GET PORT BOUNDS TOPLEFT
        CMP.L   6(A1),D0                        | IS BOUNDS TOPLEFT SAME ?
        BEQ.B   CallBits                        | YES, ITS PROBABLY TO THEPORT
| DST IS DEFINITELY NOT TO THEPORT, SO WE CAN'T USE THE CAPTURE PROC.
| StretchBits(srcBits,dstBits,srcRect,dstRect,mode,wideOpen,wideOpen,maskRgn);
| Called during boot.
NOTPORT:
        MOVE.L  A2,-(SP)                        | PUSH SRCBITS
        MOVE.L  A1,-(SP)                        | PUSH DSTBITS
        MOVE.L  18(A6),-(SP)                    | PUSH SRCRECT
        MOVE.L  14(A6),-(SP)                    | PUSH DSTRECT
        MOVE    12(A6),-(SP)                    | PUSH MODE
        MOVE.L  -0x82(A4),-(SP)                 | PUSH WIDEOPEN
        MOVE.L  (SP),-(SP)                      | PUSH WIDEOPEN
        MOVE.L  8(A6),-(SP)                     | PUSH MASKRGN
        BNE.B   NOTPORT_EMPTY                   | WAS IT NIL ?
        MOVE.L  -0x82(A4),(SP)                  | YES, REPLACE WITH WIDEOPEN
NOTPORT_EMPTY:
        JSR     StretchBits(PC)                 | CALL STRETCHBITS
        BRA.B   CALLBITS_RETURN                 | AND CONTINUE
CallBits:
        MOVE.L  A2,-(SP)                        | PUSH SRCBITS
        MOVE.L  18(A6),-(SP)                    | PUSH SRCRECT
        MOVE.L  14(A6),-(SP)                    | PUSH DSTRECT
        MOVE    12(A6),-(SP)                    | PUSH MODE
        MOVE.L  8(A6),-(SP)                     | PUSH MASKRGN (NIL OK)
        MOVE.L  0x68(A3),D0                     | IS GRAFPROCS NIL ?
        LEA     StdBits(PC),A0                  | default = STD bits proc
        BEQ.B   CALLBITS_USESTD                 | YES, USE STD PROC
        MOVE.L  D0,A0                           | dereference grafProcs
        MOVE.L  0x20(A0),A0                     | A0 := bitsProc
CALLBITS_USESTD:
        JSR     (A0)                            | CALL IT
CALLBITS_RETURN:
        CMP.L   D6,D7                           | WAS SRC FROM THE SCREEN ?
        BNE.B   NOTPORT_NO                      | NO, CONTINUE
        JSR     ShowCursor(PC)                  | YES, REPLACE CURSOR
NOTPORT_NO:
        MOVEM.L (SP)+,D6-D7/A2-A4               | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDA.W  #0x16,SP                        | strip PARAMSIZE bytes
        JMP     (A0)                            | RTS
| ----------------------------------------------------------
|
| _ScrollRect ($A8EF): scroll the bits inside a rectangle of the current port
| Pascal: PROCEDURE ScrollRect(r: Rect; dh, dv: INTEGER; updateRgn: RgnHandle);
| srcRgn := r SECT visRgn SECT clipRgn, dstRgn := srcRgn offset by (dh,dv),
| updateRgn := srcRgn - dstRgn. With the cursor shielded, copies the bits
| (RgnBlt srcCopy clipped to dstRgn and srcRgn), erases updateRgn with
| bkPat and disposes the two temporary regions. If pnVis < 0 or dh = dv
| = 0, it only sets updateRgn to empty (NOTPORT_EXIT).
|
ScrollRect:
        LINK    A6,#-0x8                        | ALLOCATE SRCRECT LOCAL
        MOVEM.L D6-D7/A3-A4,-(SP)               | SAVE REGS
        MOVE.L  (A5),A4                         | POINT TO QD GLOBALS
        MOVE.L  (A4),A3                         | GET THEPORT
        TST     0x42(A3)                        | IS PNVIS < 0 ?
        BLT.W   NOTPORT_EXIT                    | YES, QUIT FAST
        TST.L   12(A6)                          | ARE DH AND DV BOTH 0 ?
        BEQ.W   NOTPORT_EXIT                    | YES, QUIT FAST
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        JSR     NewRgn(PC)                      | ALLOCATE SRCRGN
        MOVE.L  (SP)+,D7                        | GET SRCRGN HANDLE IN D7
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        JSR     NewRgn(PC)                      | ALLOCATE DSTRGN
        MOVE.L  (SP)+,D6                        | GET DSTRGN HANDLE IN D6
        MOVE.L  D7,-(SP)                        | PUSH SRCRGN
        MOVE.L  16(A6),-(SP)                    | PUSH DSTRECT
        JSR     RectRgn(PC)                     | RectRgn(srcRgn,dstRect);
        MOVE.L  D7,-(SP)                        | PUSH SRCRGN
        MOVE.L  24(A3),-(SP)                    | PUSH VISRGN
        MOVE.L  D7,-(SP)                        | PUSH SRCRGN
        JSR     SectRgn(PC)                     | SectRgn(srcRgn,visRgn,srcRgn);
        MOVE.L  D7,-(SP)                        | PUSH SRCRGN
        MOVE.L  28(A3),-(SP)                    | PUSH CLIPRGN
        MOVE.L  D7,-(SP)                        | PUSH SRCRGN
        JSR     SectRgn(PC)                     | SectRgn(srcRgn,clipRgn,srcRgn);
        MOVE.L  D7,-(SP)                        | PUSH SRCRGN
        MOVE.L  D6,-(SP)                        | PUSH DSTRGN
        JSR     CopyRgn(PC)                     | CopyRgn(srcRgn,dstRgn);
        MOVE.L  D6,-(SP)                        | PUSH DSTRGN
        MOVE.L  12(A6),-(SP)                    | PUSH DH,DV PACKED
        JSR     OfsetRgn(PC)                    | OfsetRgn(dstRgn,dh,dv);
        MOVE.L  16(A6),A0                       | POINT TO DSTRECT
        MOVE.L  (A0)+,-8(A6)                    | COPY DSTRECT INTO SRCRECT
        MOVE.L  (A0)+,-4(A6)                    | COPY BOTTOM+RIGHT
        MOVE.L  12(A6),D0                       | GET DH IN LO WORD
        SUB     D0,-6(A6)                       | SRCRECT.LEFT -= DH
        SUB     D0,-2(A6)                       | SRCRECT.RIGHT -= DH
        SWAP    D0                              | GET DV IN LO WORD
        SUB     D0,-8(A6)                       | SRCRECT.TOP -= DV
        SUB     D0,-4(A6)                       | SRCRECT.BOTTOM -= DV
        MOVE.L  D7,-(SP)                        | PUSH SRCRGN
        MOVE.L  D6,-(SP)                        | PUSH DSTRGN
        MOVE.L  8(A6),-(SP)                     | PUSH UPDATERGN
        JSR     DiffRgn(PC)                     | DiffRgn(srcRgn,dstRgn,updateRgn);
        MOVE.L  16(A6),-(SP)                    | PUSH DSTRECT
        MOVE.L  8(A3),-(SP)                     | PUSH PORTBITS.BOUNDS.TOPLEFT
        JSR     ShieldCursor(PC)                | REMOVE CRSR IF INTERSECTS
        PEA.L     2(A3)                         | PUSH SRCBITS
        MOVE.L  (SP),-(SP)                      | PUSH DSTBITS
        PEA.L     -8(A6)                        | PUSH SRCRECT
        MOVE.L  16(A6),-(SP)                    | PUSH DSTRECT
        CLR     -(SP)                           | PUSH MODE = SRCCOPY
        CLR.L   -(SP)                           | PAT NOT USED
        MOVE.L  D6,-(SP)                        | PUSH DSTRGN
        MOVE.L  D7,-(SP)                        | PUSH SRCRGN
        MOVE.L  -0x82(A4),-(SP)                 | PUSH WIDEOPEN
        JSR     RgnBlt(PC)                      | COPY THE BITS
        PEA.L     2(A3)                         | PUSH SRCBITS
        MOVE.L  (SP),-(SP)                      | PUSH DSTBITS
        MOVE.L  16(A6),-(SP)                    | PUSH SRCRECT
        MOVE.L  (SP),-(SP)                      | PUSH DSTRECT
        MOVE    #0x8,-(SP)                      | PUSH MODE = PATCOPY
        PEA.L     0x20(A3)                      | PUSH PAT = BKPAT
        MOVE.L  8(A6),-(SP)                     | PUSH UPDATERGN
        MOVE.L  -0x82(A4),-(SP)                 | PUSH WIDEOPEN
        MOVE.L  (SP),-(SP)                      | PUSH WIDEOPEN
        JSR     RgnBlt(PC)                      | ERASE THE UPDATE RGN
        JSR     ShowCursor(PC)                  | RESTORE THE CURSOR
        MOVE.L  D7,-(SP)                        | push srcRgn handle
        JSR     DisposRgn(PC)                   | DisposeRgn(srcRgn)
        MOVE.L  D6,-(SP)                        | push dstRgn handle
        JSR      DisposRgn(PC)                  | DisposeRgn(dstRgn)
        BRA.B   SCROLLRECT_EXIT                 | skip empty branch
NOTPORT_EXIT:
        MOVE.L  8(A6),-(SP)                     | PUSH UPDATERGN HANDLE
        JSR     SetEmptyRgn(PC)                 | SET IT TO EMPTY
SCROLLRECT_EXIT:
        MOVEM.L (SP)+,D6-D7/A3-A4               | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return PC
        ADDA.W  #0xC,SP                         | strip PARAMSIZE bytes
        JMP     (A0)                            | RTS
PackBits:
        LINK    A6,#0x0                         | NO LOCAL VARS
        MOVE.L  A2,-(SP)                        | SAVE REGS
        MOVE.L  14(A6),A0                       | A0 := VAR srcPtr
        MOVE.L  (A0),A0                         | GET SRCPTR ITSELF
        MOVE.L  10(A6),A1                       | A1 := VAR dstPtr
        MOVE.L  (A1),A1                         | GET DSTPTR ITSELF
        MOVE    8(A6),D1                        | D1 := srcBytes count
        SUBQ.W  #0x1,D1                         | ADJUST FOR DBRA
        BLT.B   ENDFILL_EXIT                    | QUIT IF SRCBYTES <= 0
        MOVE.B  (A0)+,D0                        | GET FIRST BYTE OF SRC
        BRA.B   START                           | AND GO TO LOOP START

| ----------------------------------------------------------
| FILLOP
FILLOP:
        MOVE.B  -0x1(A0),D0                     | GET PREV SRC BYTE
        SUB     A0,D2                           | COMPUTE FILLOP
        ADDQ.W  #0x1,D2                         | ADJUST COUNT
        MOVE.B  D2,(A2)                         | STORE FILLOP
START:
        MOVE    A0,D2                           | REMEMBER SRCSTART
        MOVE.L  A1,A2                           | REMEMBER OPLOC
        CLR.B   (A1)+                           | RESERVE ROOM FOR OPCODE
        CMP.B   (A0),D0                         | IS NEXT SRC THE SAME ?
        BNE.B   START_LOOP                      | NO, USE COPY LOOP
        CMP.B   1(A0),D0                        | THREE IN A ROW ?
        BNE.B   START_LOOP                      | NO, USE COPY LOOP
        BRA.B   COPYOP_LOOP                     | YES, USE FILL LOOP
START_LOOP_READ:
        MOVE.B  (A0)+,D0                        | GET BYTE OF SRC
        CMP.B   (A0),D0                         | IS THE NEXT THE SAME ?
        BNE.B   START_LOOP                      | NO, CONTINUE
        CMP.B   1(A0),D0                        | THREE IN A ROW ?
        BEQ.B   COPYOP                          | YES, END OF COPY RUN
START_LOOP:
        MOVE.B  D0,(A1)+                        | store copy byte
        DBF     D1,START_LOOP_READ              | loop for bytes left
        SUB     A0,D2                           | COMPUTE COPYOP
        NEG     D2                              | NEGATE ONLY
        MOVE.B  D2,(A2)                         | INSTALL COPYOP
        BRA.B   ENDFILL_EXIT                    | AND QUIT
COPYOP:
        TST     D1                              | IS THIS THE LAST SRC BYTE ?
        BEQ.B   START_LOOP                      | YES, FINISH OFF COPY RUN
        SUB     A0,D2                           | COMPUTE COPYOP
        NOT     D2                              | NEGATE AND SUBTRACT 1
        MOVE.B  D2,(A2)                         | STORE COPYOP
        MOVE.L  A0,D2                           | REMEMBER SRCSTART
        MOVE.L  A1,A2                           | REMEMBER OPLOC
        CLR.B   (A1)+                           | RESERVE ROOM FOR OPCODE
COPYOP_LOOP:
        MOVE.B   D0,(A1)+                       | COPY THE DATA BYTE
NXTFILL:
        CMP.B   (A0)+,D0                        | IS NEXT BYTE THE SAME ?
        DBNE    D1,NXTFILL                      | LOOP TILL NOT SAME OR END SRC
        BEQ.B   NXTFILL_CONT                    | BRANCH IF SRC EXHAUSTED
        SUBQ.W  #0x1,D1                         | DEC SRC COUNTER
        BGE.B   FILLOP                          | BR IF SRC NOT EXHAUSTED
NXTFILL_CONT:
        SUB.W    A0,D2                          | jump via A0
        ADDQ.W   #0x1,D2                        | ADJUST FILLOP COUNT
        MOVE.B   D2,(A2)                        | INSTALL FILLOP
ENDFILL_EXIT:
        CLR.L   D0                              | DONE: GET READY FOR WORD
        MOVE    8(A6),D0                        | get srcBytes count
        MOVE.L  14(A6),A0                       | A0 := VAR srcPtr
        ADD.L   D0,(A0)                         | BUMP SRCPTR
        MOVE.L  10(A6),A2                       | A2 := VAR dstPtr
        MOVE.L  A1,(A2)                         | UPDATE DSTPTR
        MOVE.L  (SP)+,A2                        | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        ADDA.W  #0xA,SP                         | strip PARAMSIZE bytes
        JMP     (A0)                            | RTS
UnpackBits:
        LINK    A6,#0x0                         | NO LOCAL VARS
        MOVE.L  14(A6),A0                       | A0 := VAR srcPtr
        MOVE.L  (A0),A0                         | GET SRCPTR ITSELF
        MOVE.L  10(A6),A1                       | A1 := VAR dstPtr
        MOVE.L  (A1),A1                         | GET DSTPTR ITSELF
        MOVE    8(A6),D2                        | D2 := dstBytes count
        EXT.L    D2                             | MAKE IT LONG
        ADD.L   A1,D2                           | LIMIT := DSTPTR + BYTECOUNT
        BRA.B   UNPACKBITS_SKIP                 | START UNPACK LOOP
UNPACKBITS_CONT:
        EXT.W    D1                             | extend copy count to word
UNPACKBITS_LOOP:
        MOVE.B  (A0)+,(A1)+                     | copy 1 byte src->dst
        DBRA    D1,UNPACKBITS_LOOP              | loop for D1+1 bytes
UNPACKBITS_SKIP:
        CMPA.L  D2,A1                           | dst < limit?
        BCC.W   UNPACKBITS_DONE                 | no, finished
        MOVE.B  (A0)+,D1                        | NO, GET OPCODE
        BPL.B   UNPACKBITS_CONT                 | positive: copy run
        NEG.B   D1                              | -1..-127 --> FILL 2..128 BYTES
        BVS.B   UNPACKBITS_SKIP                 | NOP byte ($80): skip
        EXT.W    D1                             | CLEAR HI BYTE OF COUNT
        MOVE.B  (A0)+,D0                        | GET FILL DATA BYTE
UNPACKBITS_LOOP_2:
        MOVE.B  D0,(A1)+                        | FILL ONE BYTE
        DBRA    D1,UNPACKBITS_LOOP_2            | LOOP FOR FILL COUNT
        BRA.B   UNPACKBITS_SKIP                 | loop for next opcode

| ----------------------------------------------------------
| UNPACKBITS_DONE
UNPACKBITS_DONE:
        MOVE.L  A0,D0                           | SAVE UPDATED SRCPTR
        MOVE.L  14(A6),A0                       | GET BUFHANDLE
        MOVE.L  D0,(A0)                         | UPDATE VAR SRCPTR
        MOVE.L  10(A6),A0                       | A0 := VAR dstPtr
        MOVE.L  A1,(A0)                         | UPDATE VAR DSTPTR
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return PC
        ADDA.W  #0xA,SP                         | strip PARAMSIZE bytes
        JMP     (A0)                            | RTS
