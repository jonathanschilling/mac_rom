|-----------------------------------------------------------
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
StdBits:
        LINK    A6,#-0x116                      | ALLOCATE LOCAL VARS

.set PARAMSIZE, 18                              | TOTAL SIZE OF PARAMETERS
.set SRCBITS, PARAMSIZE+8-4                     | LONG, ADDR OF BITMAP
.set SRCRECT, SRCBITS-4                         | LONG, ADDR OF RECT
.set DSTRECT, SRCRECT-4                         | LONG, ADDR OF RECT
.set MODE, DSTRECT-2                            | WORD
.set MASKRGN, MODE-4                            | LONG, RGNHANDLE

.set MYBITS, -14                                | BITMAP
.set PACKBUF, MYBITS-256                        | SCANLINE PACKING BUFFER
.set SRCPTR, PACKBUF-4                          | LONG
.set DSTPTR, SRCPTR-4                           | LONG
.set VARSIZE, DSTPTR                            | TOTAL BYTES OF LOCALS

        MOVEM.L D3-D7/A2-A4,-(SP)               | SAVE REGS
        JSR     CheckPic(PC)                    | SET UP A4,A3 AND CHECK PICSAVE
        BLE     STDBITS_NOTPIC                  | BRANCH IF NOT PICSAVE
        MOVEQ   #8,D6                           | D6 := 8 (PACK THRESHOLD)

|
| TRIM SRCBITS
|
        MOVE.L  0x16(A6),A0                     | GET ADDR OF SRCBITS
        LEA.L   -0xE(A6),A1                     | POINT TO MY COPY
        MOVE.L  (A0),A3                         | GET BASEADDR

        MOVE    ROWBYTES(A0),D4                 | GET OLD ROWBYTES
        MOVE.L  0x6(A0),0x6(A1)                 | COPY BOUNDS TOP+LEFT
        MOVE.L  0xA(A0),0xA(A1)                 | COPY BOUNDS BOTTOM+RIGHT
        MOVE.L  0x12(A6),A0                     | POINT TO SRCRECT
        MOVE    (A0),D0                         | GET SRCRECT.TOP
        SUB     0x6(A1),D0                      | CALC SKIPTOP
        BLE.B   TOPOK                           | CONTINUE IF SKIPTOP NEG
        ADD     D0,0x6(A1)                      | ADJUST BOUNDS.TOP
        MULU    D4,D0                           | CALC VERT OFFSET
        ADD.L   D0,A3                           | ADJUST BASEADDR
TOPOK:
        MOVE    BOTTOM(A0),D0                   | GET SRCRECT.BOTTOM
        CMP     0xA(A1),D0                      | IS BOTTOM < BOUNDS.BOT ?
        BGE.B   BOTOK                           | NO, CONTINUE
        MOVE    D0,0xA(A1)                      | YES, TRIM BOUNDS.BOTTOM
BOTOK:
        MOVE    LEFT(A0),D0                     | GET SRCRECT.LEFT
        SUB     0x8(A1),D0                      | CALC SKIPLEFT
        BLE.B   LEFTOK                          | CONTINUE IF SKIPLEFT NEG
        LSR     #3,D0                           | DIV BY 8 FOR SKIP BYTES
        ADD     D0,A3                           | OFFSET BASEADDR HORIZ
        LSL     #3,D0                           | BYTES TIMES 8 FOR DOTS
        ADD     D0,0x8(A1)                      | ADJUST BOUNDS.LEFT
LEFTOK:
        MOVE    RIGHT(A0),D0                    | GET SRCRECT.RIGHT
        SUB     0x8(A1),D0                      | CALC DELTA RIGHT
        ADDQ.W  #0x7,D0                         | ROUND UP TO BYTE
        LSR     #3,D0                           | TO NEXT MULT OF 8
        LSL     #3,D0                           | CONVERT BACK TO DOTS
        ADD     0x8(A1),D0                      | ADD BOUNDS.LEFT BACK
        CMP     0xC(A1),D0                      | IS NEW RIGHT < BOUNDS.RIGHT ?
        BGE.B   LEFTOK_NO                       | NO, CONTINUE
        MOVE    D0,0xC(A1)                      | YES, TRIM BOUNDS.RIGHT
LEFTOK_NO:
        MOVE    0xC(A1),D5                      | GET TRIMMED RIGHT
        SUB     0x8(A1),D5                      | CALC WIDTH IN DOTS
        ADDI    #0xF,D5                         | ROUND UP TO WORD

| RIGHTOK
|
| CALC NEW ROWBYTES AFTER TRIMMING
|
        LSR     #4,D5                           | DIV BY 16
        BLE     START2_DONE                     | IGNORE IF NEWROW <= 0
        ADD     D5,D5                           | DOUBLE FOR NEW ROWBYTES
        MOVE    D5,ROWBYTES(A1)                 | COPY ROWBYTES
        MOVE.B  #0x90,-(SP)                     | BASE OPCODE FOR BitsRect
        TST.L   0x8(A6)                         | IS MASKRGN NIL ?
        BEQ.B   NOTRGN                          | YES, CONTINUE
        ADDQ.B  #0x1,(SP)                       | CHANGE TO BitsRgn OPCODE

| FIXED BUG 12/3/83, RP
NOTRGN:
        CMP     D6,D5                           | IS NEWROW < 8 ?
        BLT.B   NOPACK                          | YES, DONT BITPACK
        ADDQ.B  #0x8,(SP)                       | ADD PACKBITS FLAG TO OPCODE
NOPACK:
        JSR     PutPicByte(PC)                  | PUT OPCODE TO THEPIC
        PEA.L   -0xA(A6)                        | PUSH ADDR OF MYBITS+ROWBYTES
        MOVE    #10,-(SP)                       | PUSH BYTECOUNT = 10
        JSR     PutPicData(PC)                  | PUT ROWBYTES,BOUNDS TO THEPIC
        MOVE.L  0x12(A6),-(SP)                  | PUSH SRCRECT ADDR
        MOVE    D6,-(SP)                        | PUSH BYTECOUNT = 8
        JSR     PutPicData(PC)                  | PUT SRCRECT
        MOVE.L  0xE(A6),-(SP)                   | PUSH DSTRECT ADDR
        MOVE    D6,-(SP)                        | PUSH BYTECOUNT = 8
        JSR     PutPicData(PC)                  | PUT DSTRECT
        MOVE    0xC(A6),-(SP)                   | PUSH MODE WORD
        JSR     PutPicWord(PC)                  | PUT MODE
        TST.L   0x8(A6)                         | IS MASKRGN NIL ?
        BEQ.B   NOPACK_SKIP                     | YES, SKIP IT
        MOVE.L  0x8(A6),-(SP)                   | NO, PUSH MASKRGN
        JSR     PutPicRgn(PC)                   | PUT MASKRGN TO THEPIC

| NOMASK
|
| NOW PUT THE BITMAP DATA: IF NEWROW >= 8 THEN USE PACKBITS
|
NOPACK_SKIP:
        LEA.L   -0xE(A6),A2                     | POINT TO (TRIMMED) BITMAP
        MOVE    0xA(A2),D7                      | GET BOUNDS.BOTTOM
        SUB     0x6(A2),D7                      | CALC HEIGHT

| NOMASK
|
| NOW PUT THE BITMAP DATA: IF NEWROW >= 8 THEN USE PACKBITS
|
        CMP     D6,D5                           | IS NEWROW < 8 ?
        BLT.B   START2                          | YES, DONT TRY TO PACK
        BRA.B   START1                          | GO TO LOOP START

| ----------------------------------------------------------
|
| MORE1
|
MORE1:
        MOVE.L  A3,-0x112(A6)                   | SRCPTR := ^SCANLINE DATA
        LEA.L   -0x10E(A6),A0                   | POINT TO PACKBUF
        MOVE.L  A0,-0x116(A6)                   | DSTPTR := @PACKBUF
        PEA.L   -0x112(A6)                      | PUSH VAR SRCPTR
        PEA.L   -0x116(A6)                      | PUSH VAR DSTPTR
        MOVE    D5,-(SP)                        | PUSH SRCBYTES = NEWROW
        JSR     PackBits(PC)                    | PACK ROW INTO PACKBUF
        MOVE.L  -0x116(A6),D6                   | GET UPDATED DSTPTR
        LEA.L   -0x10E(A6),A0                   | POINT TO PACKBUF
        SUB.L   A0,D6                           | CALC PACKED BYTECOUNT
        MOVE.B  D6,-(SP)                        | PUSH PACKED BYTECOUNT
        JSR     PutPicByte(PC)                  | PUT PACKED BYTECOUNT TO THEPIC
        PEA.L   -0x10E(A6)                      | PUSH PACKBUF ADDR
        MOVE    D6,-(SP)                        | PUSH PACKED SIZE
        JSR     PutPicData(PC)                  | PUT PACKED DATA TO THEPIC
        ADD     D4,A3                           | ADD OLDROW TO BITS PTR
START1:
        DBF     D7,MORE1                        | LOOP FOR HEIGHT ROWS
        BRA.B   START2_DONE                     | SKIP TO DONE

|
| ROWBYTES < 8, DONT USE PACKBITS
|
MORE2:
        MOVE.L  A3,-(SP)                        | PUSH ADDR OF BITS
        MOVE    D5,-(SP)                        | PUSH BYTECOUNT = NEWROW
        JSR     PutPicData(PC)                  | PUT ONE ROW OF BITMAP DATA
        ADD     D4,A3                           | ADD OLDROW TO BITS PTR
START2:
        DBF     D7,MORE2                        | LOOP FOR HEIGHT ROWS
START2_DONE:
        MOVE.L  (A4),A3                         | RESTORE THEPORT PTR
STDBITS_NOTPIC:
        TST     PNVIS(A3)                       | NOTPIC: IS PNVIS >= 0 ?
        BLT.B   STDBITS_GOHOME                  | NO, QUIT
        MOVE.L  0x16(A6),-(SP)                  | PUSH SRCBITS
        PEA.L   PORTBITS(A3)                    | PUSH DSTBITS = PORTBITS
        MOVE.L  0x12(A6),-(SP)                  | PUSH SRCRECT
        MOVE.L  0xE(A6),-(SP)                   | PUSH DSTRECT
        MOVE    0xC(A6),-(SP)                   | PUSH MODE
        MOVE.L  CLIPRGN(A3),-(SP)               | PUSH CLIPRGN
        MOVE.L  VISRGN(A3),-(SP)                | PUSH VISRGN
        MOVE.L  0x8(A6),-(SP)                   | PUSH MASKRGN
        BNE.B   MASKOK                          | WAS IT NIL ?
        MOVE.L  WIDEOPEN(A4),(SP)               | YES, REPLACE WITH WIDEOPEN
MASKOK:
        JSR     StretchBits(PC)                 | CALL STRETCHBITS
STDBITS_GOHOME:
        MOVEM.L (SP)+,D3-D7/A2-A4               | GOHOME: RESTORE REGS
        UNLK    A6                              | RELEASE LOCAL VARS
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDA    #0x12,SP                        | STRIP 18 BYTES OF PARAMS
        JMP     (A0)                            | RETURN TO CALLER

| .PROC CopyBits,6
| .REF StdBits,ShieldCursor,ShowCursor,StretchBits
| ---------------------------------------------------------------
|
| PROCEDURE CopyBits(srcBits,dstBits: BitMap;
| srcRect,dstRect: Rect;
| mode: INTEGER;
| maskRgn: RgnHandle *);
|
|
| A6 OFFSETS OF PARAMS AND LOCALS AFTER LINK:
|
| PARAMSIZE .EQU 22 ;TOTAL BYTES OF PARAMS
| SRCBITS .EQU PARAMSIZE+8-4 ;LONG, ADDR OF BITMAP
| DSTBITS .EQU SRCBITS-4 ;LONG, ADDR OF BITMAP
| SRCRECT .EQU DSTBITS-4 ;LONG, ADDR OF RECT
| DSTRECT .EQU SRCRECT-4 ;LONG, ADDR OF RECT
| MODE .EQU DSTRECT-2 ;WORD
| MASKRGN .EQU MODE-4 ;LONG, RGNHANDLE
| Called during boot.
CopyBits:
.set PARAMSIZE, 22                              | TOTAL BYTES OF PARAMS
.set SRCBITS, PARAMSIZE+8-4                     | LONG, ADDR OF BITMAP
.set DSTBITS, SRCBITS-4                         | LONG, ADDR OF BITMAP
.set SRCRECT, DSTBITS-4                         | LONG, ADDR OF RECT
.set DSTRECT, SRCRECT-4                         | LONG, ADDR OF RECT
.set MODE, DSTRECT-2                            | WORD
.set MASKRGN, MODE-4                            | LONG, RGNHANDLE

        LINK    A6,#0                           | NO LOCAL VARS
        MOVEM.L D6-D7/A2-A4,-(SP)               | SAVE REGS
        MOVE.L  (A5),A4                         | POINT TO QD GLOBALS
        MOVE.L  (A4),A3                         | GET THEPORT
        MOVE.L  0x1A(A6),A2                     | POINT TO SRCBITS
        MOVE.L  (A2),D7                         | GET SRC BASEADDR
        MOVE.L  -0x7A(A4),D6                    | GET SCREEN BASEADDR
        CMP.L   D6,D7                           | IS SRC FROM THE SCREEN ?
        BNE.B   SRCOK                           | NO, CONTINUE
        MOVE.L  0x12(A6),-(SP)                  | YES, PUSH SRCRECT
        MOVE.L  0x6(A2),-(SP)                   | PUSH SRCBITS.BOUNDS.TOPLEFT
        JSR     ShieldCursor(PC)                | HIDE THE CURSOR IF IN SRCRECT

| -----------------------------------------------------
|
| TEST IF DST IS TO THEPORT, (IF SO WE CLIP)
|
| Called during boot.
SRCOK:
        MOVE.L  0x16(A6),A1                     | POINT TO DSTBITS

| -----------------------------------------------------
|
| TEST IF DST IS TO THEPORT, (IF SO WE CLIP)
|
        MOVE.L  A3,D0                           | IS THEPORT NIL ?
        BEQ.B   NOTPORT                         | YES, NOT TO THEPORT
        BTST    #0,D0                           | IS THEPORT ODD ?
        BNE.B   NOTPORT                         | YES, NOT TO THEPORT
        MOVE.L  0x2(A3),D0                      | GET PORT BASEADDR
        CMP.L   (A1),D0                         | DOES DST BASEADDR = PORT ?
        BNE.B   NOTPORT                         | NO, NOT TO THEPORT
        MOVE.L  PORTBOUNDS(A3),D0               | GET PORT BOUNDS TOPLEFT
        CMP.L   BOUNDS(A1),D0                   | IS BOUNDS TOPLEFT SAME ?
        BEQ.B   TOPORT                          | YES, ITS PROBABLY TO THEPORT

|
| DST IS DEFINITELY NOT TO THEPORT, SO WE CAN'T USE THE CAPTURE PROC.
| StretchBits(srcBits,dstBits,srcRect,dstRect,mode,wideOpen,wideOpen,maskRgn);
|
| Called during boot.
NOTPORT:
        MOVE.L  A2,-(SP)                        | PUSH SRCBITS
        MOVE.L  A1,-(SP)                        | PUSH DSTBITS
        MOVE.L  0x12(A6),-(SP)                  | PUSH SRCRECT
        MOVE.L  0xE(A6),-(SP)                   | PUSH DSTRECT
        MOVE    0xC(A6),-(SP)                   | PUSH MODE
        MOVE.L  WIDEOPEN(A4),-(SP)              | PUSH WIDEOPEN
        MOVE.L  (SP),-(SP)                      | PUSH WIDEOPEN
        MOVE.L  0x8(A6),-(SP)                   | PUSH MASKRGN
        BNE.B   COPYBITS_MASKOK                 | WAS IT NIL ?
        MOVE.L  WIDEOPEN(A4),(SP)               | YES, REPLACE WITH WIDEOPEN
COPYBITS_MASKOK:
        JSR     StretchBits(PC)                 | CALL STRETCHBITS
        BRA.B   CLEANUP                         | AND CONTINUE

|
| DST IS PROBABLY TO THEPORT, SO WE USE THE CAPTURE PROC.
| CallBits(srcBits,srcRect,dstRect,mode,maskRgn)
|
| Called during boot.
TOPORT:
        MOVE.L  A2,-(SP)                        | PUSH SRCBITS
        MOVE.L  0x12(A6),-(SP)                  | PUSH SRCRECT
        MOVE.L  0xE(A6),-(SP)                   | PUSH DSTRECT
        MOVE    0xC(A6),-(SP)                   | PUSH MODE
        MOVE.L  0x8(A6),-(SP)                   | PUSH MASKRGN (NIL OK)
        MOVE.L  GRAFPROCS(A3),D0                | IS GRAFPROCS NIL ?
        MOVE.L  (0xFAC).w,A0                    | _StdBits (bitsProc)
        BEQ.B   COPYBITS_USESTD                 | YES, USE STD PROC
        MOVE.L  D0,A0                           | POINT TO GRAFPROCS
        MOVE.L  BITSPROC(A0),A0                 | NO, GET PROC PTR
COPYBITS_USESTD:
        JSR     (A0)                            | USESTD: CALL IT
CLEANUP:
        CMP.L   D6,D7                           | WAS SRC FROM THE SCREEN ?
        BNE.B   COPYBITS_DONE                   | NO, CONTINUE
        JSR     ShowCursor(PC)                  | YES, REPLACE CURSOR
COPYBITS_DONE:
        MOVEM.L (SP)+,D6-D7/A2-A4               | DONE: RESTORE REGS
        UNLK    A6                              | RELEASE LOCAL VARS
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDA    #0x16,SP                        | STRIP 22 BYTES OF PARAMS
        JMP     (A0)                            | RETURN TO CALLER

| .PROC CopyMask
| .REF RSect,HideCursor,ShowCursor,InitRgn,SeekRgn,XorSlab
| --------------------------------------------------------------
|
| PROCEDURE CopyMask(srcBits,maskBits,dstBits: BitMap;
| srcRect,maskRect,dstRect: Rect);
|
| NEW ROUTINE ADDED TO QUICKDRAW April 28, 1985
|
| Written by Bill Atkinson. CopyRight 1985 Apple Computer Inc.
|
| A6 OFFSETS OF PARAMETERS AFTER LINK:
|
CopyMask:
        LINK    A6,#-0x5E                       | ALLOCATE LOCAL VARS
.set PARAMSIZE, 24                              | total bytes of params
.set SRCBITS, paramSize+8-4                     | long, addr of BitMap
.set MASKBITS, srcBits-4                        | long, addr of BitMap
.set DSTBITS, maskBits-4                        | long, addr of BitMap
.set SRCRECT, dstBits-4                         | long, addr of Rect
.set MASKRECT, srcRect-4                        | long, addr of Rect
.set DSTRECT, maskRect-4                        | long, addr of Rect

| -------------------------------------------------
|
| A6 OFFSETS OF LOCALS AFTER LINK:
|
.set MINRECT, -8                                | RECT
.set RGNA, MINRECT-4                            | RgnHandle
.set RGNB, RGNA-4                               | RgnHandle
.set STATEA, RGNB-RGNREC                        | REGION STATE RECORD
.set STATEB, STATEA-RGNREC                      | REGION STATE RECORD
.set BUFLEFT, STATEB-2                          | WORD
.set SRCADDR, BUFLEFT-4                         | LONG
.set MASKADDR, SRCADDR-4                        | LONG
.set DSTADDR, MASKADDR-4                        | LONG
.set SRCROW, DSTADDR-4                          | LONG
.set MASKROW, SRCROW-4                          | LONG
.set DSTROW, MASKROW-4                          | LONG
.set SAVESTK, DSTROW-4                          | LONG
.set VARSIZE, SAVESTK                           | SIZE OF LOCALS

        MOVEM.L  D0-D7/A1-A4,-(SP)              | SAVE REGS
        MOVE.L  A7,-0x5E(A6)                    | REMEMBER STACK FOR LATER
        MOVE.L  (A5),A2                         | POINT TO QD GLOBALS
        MOVE.L  WIDEOPEN(A2),-0xC(A6)           | init RGNA to wideOpen
        MOVE.L  WIDEOPEN(A2),-0x10(A6)          | init RGNB to wideOpen
        MOVE.L  (A2),A2                         | GET THEPORT
        MOVE.L  0x14(A6),A4                     | A4 POINTS TO DSTBITS
        MOVE.L  0x8(A6),A3                      | A3 POINTS TO DSTRECT
        MOVE.L  0x2(A2),D0                      | GET PORT BASEADDR
        CMP.L   (A4),D0                         | IS DST = PORT BITMAP ?

|
| if dst is in thePort, then clip to visRgn and clipRgn
|
        BNE.B   COPYMASK_NO                     | no, continue
        MOVE.L  CLIPRGN(A2),-0xC(A6)            | yes, clip to clipRgn
        MOVE.L  VISRGN(A2),-0x10(A6)            | and to visRgn

| NOTPORT
|
| CALC MINRECT, THE INTERSECTION OF DSTRECT, DSTBITS.BOUNDS,
| AND TWO REGION BOUNDING BOXES. QUIT IF RESULT IS EMPTY.
|
COPYMASK_NO:
        MOVE.L  A3,-(SP)                        | PUSH DSTRECT
        PEA.L   BOUNDS(A4)                      | PUSH DSTBITS.BOUNDS
        MOVE.L  -0xC(A6),A0                     | GET RGNHANDLE
        MOVE.L   (A0),A0                        | DE-REFERENCE IT
        PEA.L   RGNBBOX(A0)                     | PUSH BOUNDING BOX
        MOVE.L  -0x10(A6),A0                    | GET RGNHANDLE
        MOVE.L   (A0),A0                        | DE-REFERENCE IT
        PEA.L   RGNBBOX(A0)                     | PUSH BOUNDING BOX
        MOVE     #4,-(SP)                       | PUSH NRECTS = 4
        PEA.L   -0x8(A6)                        | PUSH WHERE TO PUT RESULT
        JSR     RSect(PC)                       | INTERSECT 4 RECTS
        BEQ     COPYMASK_GOHOME                 | QUIT IF EMPTY
        JSR     HideCursor(PC)                  | ELSE HIDE THE CURSOR
        MOVE    -0x6(A6),D1                     | GET MINRECT LEFT
        SUB     0x8(A4),D1                      | SUBTRACT DST BOUNDS.LEFT
        ANDI    #-0x10,D1                       | ROUND DOWN TO MULT OF 16
        ADD     0x8(A4),D1                      | ADD BACK BOUNDS.LEFT

|
| CALC BUFLEFT SO THAT RGNBUF WILL ALIGN TO DSTBITS
|
        MOVE    D1,-0x42(A6)                    | SAVE AS BUFLEFT

|
| INIT BOTH REGION STATE RECORDS AND ALLOCATE BUFFERS
|
        MOVE.L  -0xC(A6),A0                     | GET RGNHANDLE
        LEA.L   -0x28(A6),A1                    | POINT TO STATE RECORD

| AGAIN - bitmap region init loop entry: dereference rgn, init scan state, allocate scanline buffer
AGAIN:
        MOVE.L  (A0),A0                         | DE-REFERENCE RGNHANDLE
        CMPI    #0xA,(A0)                       | IS REGION RECTANGULAR ?
        SEQ      D7                             | REMEMBER FOR BELOW
        MOVE    -0x6(A6),D0                     | GET MINRECT LEFT
        MOVE    -0x2(A6),D1                     | GET MINRECT RIGHT
        MOVE    -0x42(A6),D2                    | GET BUFLEFT
        JSR     InitRgn(PC)                     | INIT STATE, ALLOC BUFFER

|
| IF REGION WAS RECTANGULAR, DRAW TOP SCANLINE INTO ITS BUFFER
| AND SET UP THISV AND NEXTV SO SEEKRGN DOES NOTHING
|
        TST.B    D7                             | was region rectangular ?
        BEQ.B   NOTRECT                         | no, continue
        MOVE    #-0x7FFF,0xE(A1)                | NEXTV := -32767
        MOVE    #0x7FFF,0x10(A1)                | ENDV := 32767
        MOVE.L   SCANBUF(A1),A0                 | point to buffer
        MOVE    -0x6(A6),D3                     | GET MINRECT LEFT
        SUB     -0x42(A6),D3                    | make buffer relative
        MOVE    -0x2(A6),D4                     | GET MINRECT RIGHT
        SUB     -0x42(A6),D4                    | make buffer relative
        JSR     XorSlab(PC)                     | draw into buffer
NOTRECT:
        LEA.L   -0x40(A6),A0                    | point to state record B
        CMP.L    A0,A1                          | did we just do RGNB ?
        BEQ.B   GETDST                          | yes, continue
        MOVE.L   A0,A1                          | no, point to STATEB
        MOVE.L  -0x10(A6),A0                    | get RGNB handle
        BRA.B   AGAIN                           | and loop to init STATEB

|
| Set up dstRow and starting dstAddr
|
GETDST:
        MOVE    ROWBYTES(A4),D1                 | get dst rowBytes
        EXT.L    D1                             | make it long
        MOVE.L  D1,-0x5A(A6)                    | save dstRow for later
        MOVE    -0x8(A6),D0                     | GET MINRECT TOP
        SUB     0x6(A4),D0                      | SUBTRACT DST BOUNDS.TOP
        MULU     D1,D0                          | mult by rowbytes
        MOVE.L  (A4),A0                         | GET DST BASEADDR
        ADD.L    D0,A0                          | add vertical offset
        MOVE    -0x6(A6),D0                     | GET MINRECT LEFT
        SUB     0x8(A4),D0                      | SUBTRACT DST BOUNDS.LEFT
        LSR      #4,D0                          | convert dots to words
        ADD      D0,D0                          | double for bytes
        ADD      D0,A0                          | add horizontal offset
        MOVE.L  A0,-0x4E(A6)                    | save result in dstAddr

|
| Set up srcRow, srcShift, and starting srcAddr
|
        MOVE.L  0x10(A6),A1                     | point to srcRect
        MOVE.L  0x1C(A6),A2                     | point to srcBits

        MOVE     ROWBYTES(A2),D1                | get src rowBytes
        EXT.L    D1                             | make it long
        MOVE.L  D1,-0x52(A6)                    | save srcRow for later
        MOVE     LEFT(A3),D6                    | get dst left
        SUB     0x8(A4),D6                      | SUBTRACT DST BOUNDS.LEFT
        MOVE     LEFT(A1),D1                    | get src left
        SUB     0x8(A2),D1                      | SUBTRACT SRC BOUNDS.LEFT
        SUB      D1,D6                          | calc delta horiz
        ANDI    #0xF,D6                         | SRCSHIFT := DELTA MOD 16
        MOVE    -0x8(A6),D0                     | GET MINRECT TOP
        SUB     (A3),D0                         | SUBTRACT DSTRECT.TOP
        ADD     (A1),D0                         | ADD SRCRECT.TOP
        SUB     0x6(A2),D0                      | SUBTRACT SRC BOUNDS.TOP
        MULU     ROWBYTES(A2),D0                | mult by src rowbytes
        MOVE.L  (A2),A0                         | GET SRC BASEADDR
        ADD.L    D0,A0                          | add vertical offset
        MOVE    -0x6(A6),D0                     | GET MINRECT LEFT
        SUB      LEFT(A3),D0                    | convert from dst coords
        ADD      LEFT(A1),D0                    | to src coords
        SUB     0x8(A2),D0                      | SUBTRACT SRC BOUNDS.LEFT
        ADD      D6,D0                          | add srcShift
        LSR      #4,D0                          | convert dots to words
        ADD      D0,D0                          | double for bytes
        ADD      D0,A0                          | add horiz offset
        MOVE.L  A0,-0x46(A6)                    | save srcAddr for later

|
| Set up maskRow, maskShift, and starting maskAddr
|
        MOVE.L  0xC(A6),A1                      | point to maskRect
        MOVE.L  0x18(A6),A2                     | point to maskBits

        MOVE     ROWBYTES(A2),D1                | get mask rowBytes
        EXT.L    D1                             | make it long
        MOVE.L  D1,-0x56(A6)                    | save maskRow for later
        MOVE     LEFT(A3),D7                    | get dst left
        SUB     0x8(A4),D7                      | SUBTRACT DST BOUNDS.LEFT
        MOVE     LEFT(A1),D1                    | get mask left
        SUB     0x8(A2),D1                      | SUBTRACT MASK BOUNDS.LEFT
        SUB      D1,D7                          | calc delta horiz
        ANDI    #0xF,D7                         | MASKSHIFT := DELTA MOD 16
        MOVE    -0x8(A6),D0                     | GET MINRECT TOP
        SUB     (A3),D0                         | SUBTRACT DSTRECT.TOP
        ADD     (A1),D0                         | ADD MASKRECT.TOP
        SUB     0x6(A2),D0                      | SUBTRACT MASK BOUNDS.TOP
        MULU     ROWBYTES(A2),D0                | mult by mask rowbytes
        MOVE.L  (A2),A0                         | GET MASK BASEADDR
        ADD.L    D0,A0                          | add vertical offset
        MOVE    -0x6(A6),D0                     | GET MINRECT LEFT
        SUB      LEFT(A3),D0                    | convert from dst coords
        ADD      LEFT(A1),D0                    | to mask coords
        SUB     0x8(A2),D0                      | SUBTRACT MASK BOUNDS.LEFT
        ADD      D7,D0                          | add maskShift
        LSR      #4,D0                          | convert dots to words
        ADD      D0,D0                          | double for bytes
        ADD      D0,A0                          | add horiz offset
        MOVE.L  A0,-0x4A(A6)                    | save maskAddr for later
        MOVE    -0x8(A6),D5                     | INIT VERT TO MINRECT.TOP

|
| MAKE REGION BUFFERS CURRENT FOR THIS VERTICAL.
| THEN SET UP AND DRAW CURRENT SCANLINE.
|
COPYMASK_NEXTROW:
        MOVE    D5,D0                           | NEXTROW: get current vert
        LEA.L   -0x28(A6),A1                    | point to state record A
        JSR     SeekRgn(PC)                     | seek region to current vert
        MOVE     D5,D0                          | get current vert
        LEA.L   -0x40(A6),A1                    | point to state record B
        JSR     SeekRgn(PC)                     | seek region to current vert
        MOVE.L  -0x20(A6),A0                    | GET STATEA SCANBUF PTR
        MOVE.L  -0x38(A6),A1                    | GET STATEB SCANBUF PTR
        MOVE.L  -0x46(A6),A2                    | init SRCPTR
        MOVE.L  -0x4A(A6),A3                    | init MASKPTR
        MOVE.L  -0x4E(A6),A4                    | init DSTPTR
        MOVE    -0x1C(A6),D3                    | GET LONG COUNT FOR LOOP
COPYMASK_NEXTROW_LOOP:
        MOVE.L  -0x2(A2),D0                     | GET SRC LONG (UNALIGNED)
        LSR.L    D6,D0                          | align to dst
        SWAP     D0                             | put result in hi word
        MOVE.L   (A2)+,D1                       | get second long of src
        LSR.L    D6,D1                          | align to dst
        MOVE    D1,D0                           | COMBINE HI AND LO SRC HALVES
        MOVE.L  -0x2(A3),D1                     | GET MASK LONG (UNALIGNED)
        LSR.L    D7,D1                          | align to dst
        SWAP     D1                             | put result in hi word
        MOVE.L   (A3)+,D2                       | get second long of mask
        LSR.L    D7,D2                          | align to dst
        MOVE    D2,D1                           | COMBINE HI AND LO MASK HALVES
        AND.L    (A0)+,D1                       | and with RGNA buffer
        AND.L    (A1)+,D1                       | and with RGNB buffer
        AND.L    D1,D0                          | mask src data
        NOT.L    D1                             | form notmask
        AND.L    (A4),D1                        | get dst data
        OR.L     D1,D0                          | merge with src data
        MOVE.L   D0,(A4)+                       | store result into dst
        DBF     D3,COPYMASK_NEXTROW_LOOP        | loop all longs this scanline

|
| bump vertically and loop for all scanlines
|
        MOVE.L  -0x52(A6),D0                    | GET SRC ROWBYTES
        ADD.L   D0,-0x46(A6)                    | BUMP SRC TO NEXT ROW
        MOVE.L  -0x56(A6),D0                    | GET MASK ROWBYTES
        ADD.L   D0,-0x4A(A6)                    | BUMP MASK TO NEXT ROW
        MOVE.L  -0x5A(A6),D0                    | GET DST ROWBYTES
        ADD.L   D0,-0x4E(A6)                    | BUMP DST TO NEXT ROW
        ADDQ.W  #0x1,D5                         | BUMP VERT
        CMP     -0x4(A6),D5                     | IS VERT < MINRECT.BOTTOM ?

  .short 0x6686                                 | BNE.B COPYMASK_NEXTROW

        JSR     ShowCursor(PC)                  | RESTORE CURSOR
COPYMASK_GOHOME:
        MOVE.L  -0x5E(A6),SP                    | STRIP VARIABLE SIZED BUFFER
        MOVEM.L  (SP)+,D0-D7/A1-A4              | RESTORE REGISTERS
        UNLK    A6                              | RELEASE LOCAL VARS
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDA    #0x18,SP                        | STRIP 24 BYTES OF PARAMS
        JMP     (A0)                            | RETURN TO CALLER

| .PROC SeedFill
| .DEF CalcMask
| -------------------------------------------------------------------------
|
| PROCEDURE SeedFill(srcPtr,dstPtr: Ptr;
| srcRow,dstRow,height,words: INTEGER;
| seedH,seedV: INTEGER)
|
SeedFill:
        MOVE.L  (SP)+,A0                        | pop return addr
        MOVEQ   #-1,D0                          | get a long of -1
        MOVE.L  D0,-(SP)                        | push edge = all ones
        BRA.B   CALCMASK_SHARE                  | share common code

| -------------------------------------------------------------------------
|
| PROCEDURE CalcMask(srcPtr,dstPtr: Ptr;
| srcRow,dstRow,height,words: INTEGER);
|
CalcMask:
        MOVE.L  (SP)+,A0                        | pop return addr
        MOVEQ    #-1,D0                         | get a long of -1
        MOVE.L   D0,-(SP)                       | push seed = (-1,-1)
        CLR.L    -(SP)                          | push edge = zeros
CALCMASK_SHARE:
        MOVE.L  A0,-(SP)                        | SHARE: restore return addr
        LINK    A6,#-0x6                        | ALLOCATE LOCAL VARS

| -------------------------------------------------------------------------
|
| LOCAL PROCEDURE MakeMask(srcPtr,dstPtr: Ptr;
| srcRow,dstRow,height,words: INTEGER;
| seedH,seedV: INTEGER;
| edge: LongInt);
|
| A6 OFFSETS OF PARAMS AND LOCALS AFTER LINK:
|
| params .EQU 24
| srcPtr .EQU params+8-4 ;long
| dstPtr .EQU srcPtr-4 ;long
| srcRow .EQU dstPtr-2 ;word
| dstRow .EQU srcRow-2 ;word
| height .EQU dstRow-2 ;word
| words .EQU height-2 ;word
| seedH .EQU words-2 ;word
| seedV .EQU seedH-2 ;word
| edge .EQU seedV-4 ;long

| dstBump .EQU -2 ;word
| saveStk .EQU dstBump-4 ;long
| varSize .EQU saveStk ;total locals
        MOVEM.L D3-D7/A2-A4,-(SP)               | save regs
        MOVE.L  A7,-0x6(A6)                     | save stack pointer

|
| prepare height and words for DBRA count. Quit if either <= 0.
|
        MOVE    0x10(A6),D5                     | get count of words

        BLE     INVERT2_EXIT                    | quit if words <= 0
        SUBQ.W  #0x1,D5                         | ADJUST FOR DBRA
        SUBQ.W  #0x1,0x12(A6)                   | ADJUST HEIGHT FOR DBRA
        BLT     INVERT2_EXIT                    | quit if height <= 0

|
| init dst to all ones:
|
        MOVE    0x10(A6),D0                     | get # of words

        ADD     D0,D0                           | double for bytes
        MOVE    0x14(A6),D1                     | get dstRow
        SUB     D0,D1                           | subtract bytes for dstBump
        MOVE    D1,-0x2(A6)                     | save dstBump for later
        MOVE.L  0x18(A6),A2                     | point to dst
        MOVEQ   #-1,D0                          | get some black
        MOVE    0x12(A6),D3                     | init DBRA rowCount
BLACK1:
        MOVE    D5,D2                           | init DBRA wordCount
BLACK2:
        MOVE    D0,(A2)+                        | put a word of black
        DBF     D2,BLACK2                       | loop all words in row
        ADD     D1,A2                           | bump to next row
        DBF     D3,BLACK1                       | loop height rows

|
| clear one dst pixel at seedH,seedV
|
        MOVE    0xC(A6),D0                      | get seed vert coord

        BLT.B   NOSEED                          | skip if neg (no seed)
        MULU    0x14(A6),D0                     | mul times dst row
        MOVE.L  0x18(A6),A0                     | point to dst
        ADDA.L  D0,A0                           | OFFSET TO SEED ROW
        MOVE    0xE(A6),D0                      | get seed horiz coord
        MOVE    D0,D1                           | copy seedH
        LSR     #3,D0                           | div by 8 for byte
        NOT     D1                              | invert bit number
        BCLR    D1,0x0(A0,D0.W)                 | CLEAR SEED PIXEL BIT

| NOSEED
|
| allocate a scanline buffer of ones or zeros on the stack:
|
NOSEED:
        MOVE.L  0x8(A6),D6                      | get zero or all ones

| NOSEED
|
| allocate a scanline buffer of ones or zeros on the stack:
|
        MOVE    D5,D1                           | get longCount
NEXTBUF:
        MOVE    D6,-(SP)                        | write a word of ones or zeros
        DBF     D1,NEXTBUF                      | loop all words
        MOVE.L  0x1C(A6),A0                     | point to top of src
        MOVE.L  0x18(A6),A2                     | point to top of dst
NXTPASS:
        SF      D7                              | clear dirty flag
        MOVE    0x12(A6),D4                     | get DBRA rowCount
        MOVE.L  SP,A1                           | point dst above to edgeBuf

|
| smear dst zeros down and to the right, smear limited by src.
|
CALCMASK_NEXTROW:
        MOVE.L  D6,D1                           | NEXTROW: init prev dst to edge
        MOVE    D5,D3                           | get DBRA wordCount
RNEXT:
        MOVE    (A2),D1                         | get dst word
        BNE.B   RDSTOK                          | is it already zero ?
        ADDQ.W  #0x2,A0                         | SKIP SRC WORD
        ADDQ.W  #0x2,A1                         | SKIP ABOVE WORD
        ADDQ.W  #0x2,A2                         | SKIP DST WORD
        SWAP    D1                              | put prev dst in hi word
        DBF     D3,RNEXT                        | loop all words in row
        BRA     LSMEAR                          | and continue below

| ----------------------------------------------------------
|
| RDSTOK
|
RDSTOK:
        MOVE    (A0)+,D2                        | get src word
        AND     (A1)+,D1                        | smear zeros down
        OR      D2,D1                           | limit vertical smear by src
        BRA.B   RSTART                          | go to loop start

| ----------------------------------------------------------
|
| RMORE
|
RMORE:
        MOVE    D0,D1                           | update dst
RSTART:
        MOVE.L  D1,D0                           | copy dst and prev dst word
        LSR.L   #1,D0                           | shift right with carry from prev
        AND     D1,D0                           | smear zeros to the right
        OR      D2,D0                           | limit smear by src
        CMP     D1,D0                           | any changes ?
        BNE.B   RMORE                           | yes, keep smearing
        CMP     (A2),D1                         | has dst changed ?
        BEQ.B   RSAME                           | no, leave it alone
        ST      D7                              | yes, set dirty flag
RSAME:
        MOVE    D1,(A2)+                        | write dst to memory
        SWAP    D1                              | put prev dst in hi word
        DBF     D3,RNEXT                        | loop all words in row

| RDONE

|
| smear dst zeros down and to the left, smear limited by src.
|
LSMEAR:
        MOVE.L  D6,D1                           | init prev dst to edge
        MOVE    D5,D3                           | get DBRA wordCount
LNEXT:
        MOVE    -(A2),D1                        | get dst word
        BNE.B   LDSTOK                          | is dst already zero ?
        SUBQ.W  #0x2,A0                         | BACK UP SRC WORD
        SUBQ.W  #0x2,A1                         | BACK UP ABOVE WORD
        SWAP    D1                              | put prev dst in hi word
        DBF     D3,LNEXT                        | loop all words in row
        BRA.B   LSAME_CONT                      | and continue

| ----------------------------------------------------------
|
| LDSTOK
|
LDSTOK:
        MOVE    -(A0),D2                        | get src word
        AND     -(A1),D1                        | smear zeros down
        OR      D2,D1                           | limit vertical smear by src
        BRA.B   LSTART                          | go to loop start

| ----------------------------------------------------------
|
| LMORE
|
LMORE:
        MOVE    D0,D1                           | update dst
LSTART:
        MOVE.L  D1,D0                           | copy dst and prev dst word
        ROL.L   #1,D0                           | shift left with carry from prev
        AND     D1,D0                           | smear zeros to the left
        OR      D2,D0                           | limit smear by src
        CMP     D1,D0                           | any changes ?
        BNE.B   LMORE                           | yes, keep smearing
        CMP     (A2),D1                         | has dst changed ?
        BEQ.B   LSAME                           | no, leave it alone
        ST      D7                              | yes, set dirty flag
        MOVE    D1,(A2)                         | write dst to memory
LSAME:
        SWAP    D1                              | put prev dst in hi word
        DBF     D3,LNEXT                        | loop all words in row

| LDONE
|
| bump three pointers down and loop for height scanlines
|
LSAME_CONT:
        ADDA    0x16(A6),A0                     | bump srcPtr down a row
        ADDA    0x14(A6),A2                     | bump dstPtr down a row

| LDONE
|
| bump three pointers down and loop for height scanlines
|
        MOVE.L  A2,A1                           | copy dstPtr
        SUBA    0x14(A6),A1                     | point to dst above
        DBF     D4,CALCMASK_NEXTROW             | loop all rows

|
| switch directions, adjust pointers, and loop till no change
|
        NEG     0x16(A6)                        | reverse src bump
        NEG     0x14(A6)                        | reverse dst bump
        ADDA    0x16(A6),A0                     | offset first src scanline
        ADDA    0x14(A6),A2                     | offset first dst scanline

        TST.B   D7                              | did anything change this pass ?
        BNE     NXTPASS                         | yes go for another pass

|
| if seedFill, then invert dst
|
        TST     D6                              | is edge = black ?
        BPL.B   INVERT2_EXIT                    | no, we're done
        MOVE    -0x2(A6),D1                     | get dstBump
        MOVE.L  0x18(A6),A2                     | point to dst
        MOVE    0x12(A6),D3                     | init DBRA rowCount
INVERT1:
        MOVE    D5,D2                           | init DBRA wordCount
INVERT2:
        NOT     (A2)+                           | invert a word of dst
        DBF     D2,INVERT2                      | loop all words in row
        ADD     D1,A2                           | bump to next row
        DBF     D3,INVERT1                      | loop height rows
INVERT2_EXIT:
        MOVE.L  -0x6(A6),SP                     | restore stack pointer
        MOVEM.L (SP)+,D3-D7/A2-A4               | restore regs
        UNLK    A6                              | release stack frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDA    #0x18,SP                        | STRIP 24 BYTES OF PARAMS
        JMP     (A0)                            | and return

| .PROC ScrollRect,4
| .REF NewRgn,RectRgn,SectRgn,CopyRgn,OffsetRgn,SetEmptyRgn
| .REF DiffRgn,ShieldCursor,RgnBlt,ShowCursor
| ---------------------------------------------------------------------
|
| PROCEDURE ScrollRect(dstRect: Rect; dh,dv: INTEGER; updateRgn: RgnHandle);
|
| Scroll a rectangular block of bits, erase and return an update region
|
| A6 OFFSETS OF PARAMS AND LOCALS AFTER LINK:
|
| PARAMSIZE .EQU 12 ;TOTAL BYTES OF PARAMS
| DSTRECT .EQU PARAMSIZE+8-4 ;LONG, ADDR OF RECT
| DH .EQU DSTRECT-2 ;WORD
| DV .EQU DH-2 ;WORD
| UPDATERGN .EQU DV-4 ;LONG, RGNHANDLE
ScrollRect:
        LINK    A6,#-0x8                        | ALLOCATE SRCRECT LOCAL

| SRCRECT .EQU -8 ;RECT
| VARSIZE .EQU SRCRECT ;TOTAL LOCALS
.set PARAMSIZE, 12                              | TOTAL BYTES OF PARAMS
.set DSTRECT, PARAMSIZE+8-4                     | LONG, ADDR OF RECT
.set DH, DSTRECT-2                              | WORD

| .set DV, DH-2 ;WORD
.set UPDATERGN, DV-4                            | LONG, RGNHANDLE

.set SRCRECT, -8                                | RECT
.set VARSIZE, SRCRECT                           | TOTAL LOCALS

        MOVEM.L D6-D7/A3-A4,-(SP)               | SAVE REGS
        MOVE.L  (A5),A4                         | POINT TO QD GLOBALS
        MOVE.L  (A4),A3                         | GET THEPORT
        TST     PNVIS(A3)                       | IS PNVIS < 0 ?
        BLT     ABORT                           | YES, QUIT FAST
        TST.L   0xC(A6)                         | IS DSTRECT NIL ?
        BEQ     ABORT                           | YES, QUIT FAST
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        JSR     NewRgn(PC)                      | ALLOCATE SRCRGN
        MOVE.L  (SP)+,D7                        | GET SRCRGN HANDLE IN D7
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        JSR     NewRgn(PC)                      | ALLOCATE DSTRGN
        MOVE.L  (SP)+,D6                        | GET DSTRGN HANDLE IN D6

|
| srcRgn := dstRect SectScan visRgn SectScan clipRgn
|
        MOVE.L  D7,-(SP)                        | PUSH SRCRGN
        MOVE.L  0x10(A6),-(SP)                  | PUSH DSTRECT
        JSR     RectRgn(PC)                     | RectRgn(srcRgn,dstRect);
        MOVE.L  D7,-(SP)                        | PUSH SRCRGN
        MOVE.L  VISRGN(A3),-(SP)                | PUSH VISRGN
        MOVE.L  D7,-(SP)                        | PUSH SRCRGN
        JSR     SectRgn(PC)                     | SectRgn(srcRgn,visRgn,srcRgn);
        MOVE.L  D7,-(SP)                        | PUSH SRCRGN
        MOVE.L  CLIPRGN(A3),-(SP)               | PUSH CLIPRGN
        MOVE.L  D7,-(SP)                        | PUSH SRCRGN
        JSR     SectRgn(PC)                     | SectRgn(srcRgn,clipRgn,srcRgn);

|
| dstRgn := offset srcRgn
|
        MOVE.L  D7,-(SP)                        | PUSH SRCRGN
        MOVE.L  D6,-(SP)                        | PUSH DSTRGN
        JSR     CopyRgn(PC)                     | CopyRgn(srcRgn,dstRgn);
        MOVE.L  D6,-(SP)                        | PUSH DSTRGN
        MOVE.L  0xC(A6),-(SP)                   | PUSH DH,DV PACKED
        JSR     OffsetRgn(PC)                   | OffsetRgn(dstRgn,dh,dv);
        MOVE.L  0x10(A6),A0                     | POINT TO DSTRECT
        MOVE.L  (A0)+,-0x8(A6)                  | COPY DSTRECT INTO SRCRECT
        MOVE.L  (A0)+,-0x4(A6)                  | COPY BOTTOM+RIGHT
        MOVE.L  0xC(A6),D0                      | GET DH IN LO WORD
        SUB     D0,-0x6(A6)                     | SRCRECT.LEFT -= DH
        SUB     D0,-0x2(A6)                     | SRCRECT.RIGHT -= DH
        SWAP    D0                              | GET DV IN LO WORD
        SUB     D0,-0x8(A6)                     | SRCRECT.TOP -= DV
        SUB     D0,-0x4(A6)                     | SRCRECT.BOTTOM -= DV

|
| Compute updateRgn := srcRgn - dstRgn
|
        MOVE.L  D7,-(SP)                        | PUSH SRCRGN
        MOVE.L  D6,-(SP)                        | PUSH DSTRGN
        MOVE.L  0x8(A6),-(SP)                   | PUSH UPDATERGN
        JSR     DiffRgn(PC)                     | DiffRgn(srcRgn,dstRgn,updateRgn);

|
| ShieldCursor(dstRect,portBits.bounds.topLeft); { protect source }
|
        MOVE.L  0x10(A6),-(SP)                  | PUSH DSTRECT
        MOVE.L  0x8(A3),-(SP)                   | PUSH PORTBITS.BOUNDS.TOPLEFT

        JSR     ShieldCursor(PC)                | REMOVE CRSR IF INTERSECTS

|
| Copy all bits which are in both srcRgn and dstRgn.
| RgnBlt(portBits,portBits,srcRect,dstRect,0,white,dstRgn,srcRgn,wideOpen);
|
        PEA.L   PORTBITS(A3)                    | PUSH SRCBITS
        MOVE.L  (SP),-(SP)                      | PUSH DSTBITS
        PEA.L   -0x8(A6)                        | PUSH SRCRECT
        MOVE.L  0x10(A6),-(SP)                  | PUSH DSTRECT
        CLR     -(SP)                           | PUSH MODE = SRCCOPY
        CLR.L   -(SP)                           | PAT NOT USED
        MOVE.L  D6,-(SP)                        | PUSH DSTRGN
        MOVE.L  D7,-(SP)                        | PUSH SRCRGN
        MOVE.L  WIDEOPEN(A4),-(SP)              | PUSH WIDEOPEN
        JSR     RgnBlt(PC)                      | COPY THE BITS

|
| Erase the update region
| RgnBlt(portBits,portBits,dstRect,dstRect,8,bkPat,updateRgn,wideOpen,wideOpen);
|
        PEA.L   PORTBITS(A3)                    | PUSH SRCBITS
        MOVE.L  (SP),-(SP)                      | PUSH DSTBITS
        MOVE.L  0x10(A6),-(SP)                  | PUSH SRCRECT
        MOVE.L  (SP),-(SP)                      | PUSH DSTRECT
        MOVE    #8,-(SP)                        | PUSH MODE = PATCOPY
        PEA.L   BKPAT(A3)                       | PUSH PAT = BKPAT
        MOVE.L  0x8(A6),-(SP)                   | PUSH UPDATERGN
        MOVE.L  WIDEOPEN(A4),-(SP)              | PUSH WIDEOPEN
        MOVE.L  (SP),-(SP)                      | PUSH WIDEOPEN
        JSR     RgnBlt(PC)                      | ERASE THE UPDATE RGN
        JSR     ShowCursor(PC)                  | RESTORE THE CURSOR
        MOVE.L  D7,A0                           | GET SRCRGN
        _DisposeHandle                          | DISCARD SRCRGN

| _DisposHandle ;DISCARD IT
        MOVE.L  D6,A0                           | PUSH DSTRGN
        _DisposeHandle                          | DISCARD DSTRGN
        BRA.B   ABORT_DONE                      | SKIP TO DONE

| ----------------------------------------------------------
|
| ABORT
|
ABORT:
        MOVE.L  0x8(A6),-(SP)                   | PUSH UPDATERGN HANDLE
        JSR     SetEmptyRgn(PC)                 | SET IT TO EMPTY
ABORT_DONE:
        MOVEM.L (SP)+,D6-D7/A3-A4               | DONE: RESTORE REGS
        UNLK    A6                              | RELEASE LOCAL VARS
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDA    #0xC,SP                         | STRIP 12 BYTES OF PARAMS
        JMP     (A0)                            | RETURN TO CALLER

| .PROC PackBits
| .DEF UnpackBits
| ---------------------------------------------------------------------
|
| PROCEDURE PackBits(VAR srcPtr,dstPtr: Ptr; srcBytes: INTEGER);
|
| Packs one scanline of data, compressing equal bytes.
| Returns updated srcPtr and dstPtr.
|
| Equates for parameters are shared with UnpackBits
|
| PARAMSIZE .EQU 10 ;TOTAL BYTES OF PARAMS
| SRCPTR .EQU PARAMSIZE+4-4 ;LONG, VAR
| DSTPTR .EQU SRCPTR-4 ;LONG,VAR
| SRCBYTES .EQU DSTPTR-2 ;WORD
| DSTBYTES .EQU SRCBYTES ;ALIAS
PackBits:
.set PARAMSIZE, 10                              | TOTAL BYTES OF PARAMS
.set SRCPTR, PARAMSIZE+4-4                      | LONG, VAR
.set DSTPTR, SRCPTR-4                           | LONG,VAR
.set SRCBYTES, DSTPTR-2                         | WORD
.set DSTBYTES, SRCBYTES                         | ALIAS

        MOVE.L  A2,-(SP)                        | SAVE REGS
        MOVE.L  0xE(SP),A0                      | GET ADDR OF SRCPTR VAR
        MOVE.L  (A0),A0                         | GET SRCPTR ITSELF
        MOVE.L  0xA(SP),A1                      | GET ADDR OF DSTPTR VAR
        MOVE.L  (A1),A1                         | GET DSTPTR ITSELF
        MOVE    0x8(SP),D1                      | GET SRCBYTES
        SUBQ.W  #0x1,D1                         | ADJUST FOR DBRA
        BLT.B   ENDFILL_EXIT                    | QUIT IF SRCBYTES <= 0
        MOVE.B  (A0)+,D0                        | GET FIRST BYTE OF SRC
        BRA.B   START                           | AND GO TO LOOP START

| ----------------------------------------------------------
|
| FILLOP
|
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
        BNE.B   DOCOPY                          | NO, USE COPY LOOP
        CMP.B   0x1(A0),D0                      | THREE IN A ROW ?
        BNE.B   DOCOPY                          | NO, USE COPY LOOP
        BRA.B   DOFILL                          | YES, USE FILL LOOP

| ----------------------------------------------------------
|
| NXTCOPY
|
NXTCOPY:
        MOVE.B  (A0)+,D0                        | GET BYTE OF SRC
        CMP.B   (A0),D0                         | IS THE NEXT THE SAME ?
        BNE.B   DOCOPY                          | NO, CONTINUE
        CMP.B   0x1(A0),D0                      | THREE IN A ROW ?
        BEQ.B   COPYOP                          | YES, END OF COPY RUN
DOCOPY:
        MOVE.B  D0,(A1)+                        | COPY DATA TO DST
        DBF     D1,NXTCOPY                      | AND LOOP FOR MORE
ENDCOPY:
        SUB     A0,D2                           | COMPUTE COPYOP
        NEG     D2                              | NEGATE ONLY
        MOVE.B  D2,(A2)                         | INSTALL COPYOP
        BRA.B   ENDFILL_EXIT                    | AND QUIT

| ----------------------------------------------------------
|
| COPYOP
|
COPYOP:
        TST     D1                              | IS THIS THE LAST SRC BYTE ?
        BEQ.B   DOCOPY                          | YES, FINISH OFF COPY RUN
        SUB     A0,D2                           | COMPUTE COPYOP
        NOT     D2                              | NEGATE AND SUBTRACT 1
        MOVE.B  D2,(A2)                         | STORE COPYOP
        MOVE.L  A0,D2                           | REMEMBER SRCSTART
        MOVE.L  A1,A2                           | REMEMBER OPLOC
        CLR.B   (A1)+                           | RESERVE ROOM FOR OPCODE
DOFILL:
        MOVE.B  D0,(A1)+                        | COPY THE DATA BYTE
NXTFILL:
        CMP.B   (A0)+,D0                        | IS NEXT BYTE THE SAME ?
        DBNE    D1,NXTFILL                      | LOOP TILL NOT SAME OR END SRC
        BEQ.B   ENDFILL                         | BRANCH IF SRC EXHAUSTED
        SUBQ.W  #0x1,D1                         | DEC SRC COUNTER
        BGE.B   FILLOP                          | BR IF SRC NOT EXHAUSTED
ENDFILL:
        SUB     A0,D2                           | COMPUTE FILLOP
        ADDQ.W  #0x1,D2                         | ADJUST COUNT
        MOVE.B  D2,(A2)                         | INSTALL FILLOP
ENDFILL_EXIT:
        CLR.L   D0                              | DONE: GET READY FOR WORD
        MOVE    0x8(SP),D0                      | GET SRCBYTES
        MOVE.L  0xE(SP),A0                      | GET ADDR OF SRCPTR VAR
        ADD.L   D0,(A0)                         | BUMP SRCPTR
        MOVE.L  0xA(SP),A2                      | GET ADDR OF DSTPTR VAR
        MOVE.L  A1,(A2)                         | UPDATE DSTPTR
        MOVE.L  (SP)+,A2                        | RESTORE REGS
ENDFILL_EXIT_2:
        MOVE.L  (SP)+,A0                        | SHARE: POP RETURN ADDR
        ADDA    #0xA,SP                         | STRIP 10 BYTES OF PARAMS
        JMP     (A0)                            | AND RETURN

| --------------------------------------------------------
|
| PROCEDURE UnpackBits(VAR srcPtr,dstPtr: Ptr; dstBytes: INTEGER);
|
| Unpacks one scanline of data, as compressed by PackBits.
| Returns updated srcPtr and dstPtr.
|
| Equates for parameters are the same as PackBits!
|
UnpackBits:
        MOVE.L  0xA(SP),A0                      | GET ADDR OF SRCPTR

| --------------------------------------------------------
|
        MOVE.L  (A0),A0                         | GET SRCPTR ITSELF
        MOVE.L  0x6(SP),A1                      | GET ADDR OF DSTPTR
        MOVE.L  (A1),A1                         | GET DSTPTR ITSELF
        MOVE    0x4(SP),D2                      | GET DSTBYTES
        EXT.L   D2                              | MAKE IT LONG
        ADD.L   A1,D2                           | LIMIT := DSTPTR + BYTECOUNT
        BRA.B   UNPACKBITS_SKIP                 | START UNPACK LOOP

| ----------------------------------------------------------
|
| UNPACKBITS_CONT
|
UNPACKBITS_CONT:
        EXT     D1                              | SIGN EXTEND COPY COUNT
UNPACKBITS_LOOP:
        MOVE.B  (A0)+,(A1)+                     | COPY ONE BYTE FROM SRC TO DST
        DBF     D1,UNPACKBITS_LOOP              | LOOP FOR COPY COUNT
UNPACKBITS_SKIP:
        CMPA.L  D2,A1                           | HAS DST REACHED LIMIT ?
        BCC.B   UNPACKBITS_DONE                 | YES, DONE
        MOVE.B  (A0)+,D1                        | NO, GET OPCODE
        BPL.B   UNPACKBITS_CONT                 | 0..127 --> COPY 1..128 BYTES
        NEG.B   D1                              | -1..-127 --> FILL 2..128 BYTES
        BVS.B   UNPACKBITS_SKIP                 | SKIP IF -128 (NOP)
        EXT     D1                              | SIGN EXTEND FILL COUNT
        MOVE.B  (A0)+,D0                        | GET FILL DATA BYTE
UNPACKBITS_LOOP_2:
        MOVE.B  D0,(A1)+                        | FILL ONE BYTE
        DBF     D1,UNPACKBITS_LOOP_2            | LOOP FOR FILL COUNT
        BRA.B   UNPACKBITS_SKIP                 | CHECK IF MORE TO UNPACK

| ----------------------------------------------------------
|
| UNPACKBITS_DONE
|
UNPACKBITS_DONE:
        MOVE.L  A0,D0                           | SAVE UPDATED SRCPTR
        MOVE.L  0xA(SP),A0                      | GET VAR ADDR
        MOVE.L  D0,(A0)                         | UPDATE VAR SRCPTR
        MOVE.L  0x6(SP),A0                      | GET VAR ADDR
        MOVE.L  A1,(A0)                         | UPDATE VAR DSTPTR
        BRA.B   ENDFILL_EXIT_2                  | SHARE COMMON EXIT


