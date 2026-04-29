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
.set PARAMSIZE, 8                               | TOTAL BYTES OF PARAMS
.set KIND, PARAMSIZE+8-2                        | WORD
.set DATASIZE, KIND-2                           | WORD
.set DATAHANDLE, DATASIZE-4                     | LONG, HANDLE

        LINK    A6,#0                           | NO LOCAL VARS
        MOVEM.L D6-D7,-(SP)                     | SAVE REGS
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        TST.L   PICSAVE(A0)                     | ARE WE SAVING FOR THEPIC ?
        BEQ.B   STDCOMMENT_DONE                 | NO, QUIT
        MOVE    0xE(A6),D6                      | YES, GET KIND
        MOVE    0xC(A6),D7                      | IS DATASIZE > 0 ?
        BGT.B   STDCOMMENT_OK                   | YES, USE LONG FORMAT
        MOVEQ.L #-0x60,D0                       | PUT SHORT COMMENT OPCODE

|
| DATASIZE 0, USE SHORT FORMAT
|
        JSR     DPutPicByte(PC)                 | PUT SHORT COMMENT OPCODE
        MOVE    D6,-(SP)                        | PUSH KIND
        JSR     PutPicWord(PC)                  | PUT KIND
        BRA.B   STDCOMMENT_DONE                 | GO TO END

| ----------------------------------------------------------
|
| STDCOMMENT_OK
|
STDCOMMENT_OK:
        MOVEQ.L #-0x5F,D0                       | PUT LONG COMMENT OPCODE

|
| DATASIZE > 0, USE LONG FORMAT
|
        JSR     DPutPicByte(PC)                 | PUT LONG COMMENT OPCODE
        MOVE    D6,-(SP)                        | PUSH KIND
        JSR     PutPicWord(PC)                  | PUT KIND
        MOVE    D7,-(SP)                        | PUSH DATASIZE
        JSR     PutPicWord(PC)                  | PUT DATASIZE
        MOVE.L  0x8(A6),A0                      | GET DATA HANDLE
        _HLock                                  | LOCK IT
        MOVE.L  0x8(A6),A0                      | GET DATA HANDLE
        MOVE.L  (A0),-(SP)                      | PUSH DATAPTR
        MOVE    D7,-(SP)                        | PUSH BYTECOUNT
        JSR     PutPicData(PC)                  | PUT DATA TO THEPIC
        MOVE.L  0x8(A6),A0                      | GET DATA HANDLE
        _HUnlock                                | UNLOCK IT
STDCOMMENT_DONE:
        MOVEM.L (SP)+,D6-D7                     | DONE: RESTORE REGS
        UNLK    A6                              | RESTORE STACK FRAME
        MOVE.L  (SP)+,A0                        | GET RETURN ADDRESS
        ADDQ.W  #0x8,SP                         | POP PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER

| .PROC StdGetPic
| ------------------------------------------------------------------
|
| PROCEDURE StdGetPic(dataPtr: QDPtr; byteCount: INTEGER);
|
StdGetPic:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE    (SP)+,D1                        | POP BYTECOUNT
        MOVE.L  (SP)+,A1                        | POP DATAPTR
        MOVE.L  A0,-(SP)                        | PUSH RETURN ADDR
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  PLAYINDEX(A0),D0                | GET PLAYINDEX
        EXT.L   D1                              | EXTEND BYTECOUNT TO LONG
        ADD.L   D1,PLAYINDEX(A0)                | BUMP PLAYINDEX
        MOVE.L  PLAYPIC(A0),A0                  | GET PLAY PICHANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        ADD.L   D0,A0                           | ADD PLAYINDEX
        BRA.B   STDGETPIC_START                 | GO TO LOOP START

| ----------------------------------------------------------
|
| NXTBYTE
|
NXTBYTE:
        MOVE.B  (A0)+,(A1)+                     | COPY ONE BYTE
STDGETPIC_START:
        DBF     D1,NXTBYTE                      | LOOP FOR ALL BYTES
        RTS                                     | RETURN TO CALLER

| .PROC StdPutPic,1
| .REF SetSize
| ------------------------------------------------------------------
|
| PROCEDURE StdPutPic(dataPtr: QDPtr; byteCount: INTEGER);
|
| Append some picture bytes to a growing handle.
|
| PARAMSIZE .EQU 6
| SRCPTR .EQU PARAMSIZE+8-4 ;LONG
| BYTECOUNT .EQU SRCPTR-2 ;WORD
StdPutPic:
.set PARAMSIZE, 6                               | TOTAL BYTES OF PARAMS
.set SRCPTR, PARAMSIZE+8-4                      | LONG
.set BYTECOUNT, SRCPTR-2                        | WORD

        LINK    A6,#0                           | NO LOCALS
        MOVEM.L D7/A3-A4,-(SP)                  | SAVE REGS
        MOVE.L  (A5),A4                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A4),A4                         | GET CURRENT GRAFPORT
        TST.L   PICSAVE(A4)                     | ARE WE SAVING FOR A PICTURE ?
        BEQ.B   STDPUTPIC_GOHOME                | NO, QUIT
        MOVE.L  PICSAVE(A4),A4                  | YES, GET PICSAVE HANDLE
        MOVE.L  (A4),A1                         | DE-REFERENCE PICSAVE HANDLE
        MOVE.L  PICINDEX(A1),D7                 | GET CURRENT SIZE
        BEQ.B   STDPUTPIC_GOHOME                | QUIT IF PICTURE IS ALREADY DEAD
        MOVE.L  (A1),A3                         | GET THEPIC HANDLE
        MOVE    0x8(A6),D0                      | GET BYTES REQUESTED
        EXT.L   D0                              | MAKE BYTECOUNT LONG
        ADD.L   D7,D0                           | CALCULATE NEW SIZE
        MOVE.L  D0,PICINDEX(A1)                 | UPDATE PICINDEX
        MOVE.L  (A3),A0                         | DE-REFERENCE THEPIC
        MOVE    D0,(A0)                         | PICSIZE := LO WORD OF PICINDEX
        CMP.L   PICMAX(A1),D0                   | IS NEW SIZE > PICMAX ?
        BLE.B   STDPUTPIC_ERR                   | NO, CONTINUE
        ADDI.L  #0x100,D0                       | GROW PIC IN CHUNKS

|
| time to grow the picture in chunks of at least 256 bytes
|
        MOVE.L  D0,PICMAX(A1)                   | UPDATE NEW PICMAX
        MOVE.L  A3,A0                           | GET THEPIC HANDLE
        _SetHandleSize                          | MAKE IT BIGGER
        MOVE.L  (A4),A1                         | RE-DEREFERENCE PICSAVE HANDLE
        BEQ.B   STDPUTPIC_ERR                   | CONTINUE IF NO ERROR

|
| Failed to grow picture, so we will trim handle down to 10 bytes,
| clear PicIndex, and set picSize to -1, PicFrame to (0,0,0,0).
|
        CLR.L   PICINDEX(A1)                    | CLEAR PICINDEX AS DEAD FLAG
        MOVEQ.L #0xA,D0                         | BYTECOUNT = 10
        MOVE.L  A3,A0                           | GET THEPIC HANDLE
        _SetHandleSize                          | SHRINK PICTURE TO 10 BYTES
        MOVE.L  (A3),A0                         | DE-REFERENCE PICHANDLE
        MOVE    #-1,(A0)+                       | STUFF picSize = -1
        CLR.L   (A0)+                           | stuff picFrame = (0,0,0,0)
        CLR.L   (A0)+                           | all 8 bytes of picFrame
        BRA.B   STDPUTPIC_GOHOME                | AND QUIT

| ----------------------------------------------------------
|
| STDPUTPIC_ERR
|
STDPUTPIC_ERR:
        MOVE.L  (A1),A1                         | DEREFERENCE HANDLE

|
| now copy the data bytes into the picture:
|
        MOVE.L  (A1),A1                         | DE-REFERENCE PICHANDLE
        ADD.L   D7,A1                           | ADD OLDSIZE FOR DSTPTR
        MOVE.L  0xA(A6),A0                      | GET SRCPTR
        MOVE    0x8(A6),D0                      | GET BYTECOUNT
        BRA.B   STDPUTPIC_START                 | GO TO LOOP START

| ----------------------------------------------------------
|
| STDPUTPIC_NXTBYTE
|
STDPUTPIC_NXTBYTE:
        MOVE.B  (A0)+,(A1)+                     | NXTBYTE: COPY A BYTE
STDPUTPIC_START:
        DBF     D0,STDPUTPIC_NXTBYTE            | LOOP ALL BYTES
STDPUTPIC_GOHOME:
        MOVEM.L (SP)+,D7/A3-A4                  | GOHOME: RESTORE REGS
        UNLK    A6                              | RESTORE STACK FRAME
        MOVE.L  (SP)+,A0                        | GET RETURN ADDRESS
        ADDQ.W  #0x6,SP                         | POP PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER

| .PROC PicComment,3
| .REF StdComment
| ------------------------------------------------------------------
|
| PROCEDURE PicComment(kind,dataSize: INTEGER; dataHandle: Handle;
|
PicComment:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE.L  GRAFPROCS(A0),D0                | IS GRAFPROCS NIL ?
        MOVE.L  (0xFC4).w,A0                    | _StdComment (commentProc)
        BEQ.B   PICCOMMENT_USESTD               | YES, USE STDCOMMENT
        MOVE.L  D0,A0                           | COPY POINTER
        MOVE.L  COMMENTPROC(A0),A0              | NO, GET PROC PTR
PICCOMMENT_USESTD:
        JMP     (A0)                            | USESTD: AND JUMP TO IT

| .FUNC OpenPicture,1
| .REF HidePen,NewRgn,PutPicWord,EqualRgn,ClipRect
| ------------------------------------------------------------------
|
| FUNCTION OpenPicture(picFrame: Rect): PicHandle;
|
| A6 OFFSETS OF PARAMS AFTER LINK:
|
| PARAMSIZE .EQU 4
| RESULT .EQU PARAMSIZE+8 ;LONG, PICHANDLE
| RECT .EQU RESULT-4 ;LONG, ADDR OF RECT
OpenPicture:
.set PARAMSIZE, 4                               | TOTAL BYTES OF PARAMS
.set RESULT, PARAMSIZE+8                        | LONG, PICHANDLE
.set RECT, RESULT-4                             | LONG, ADDR OF RECT

        LINK    A6,#0                           | NO LOCALS
        MOVEM.L A3-A4,-(SP)                     | SAVE REGS
        CLR.L   0xC(A6)                         | INIT FCN RESULT TO NIL
        MOVE.L  (A5),A4                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A4),A3                         | GET CURRENT GRAFPORT
        TST.L   PICSAVE(A3)                     | ARE WE ALREADY SAVING ?

|
| Abort OpenPicture if heap doesn't have at least 500 bytes.
|
| _NewHandle ;AT LEAST 500 BYTES IN THE HEAP ?
        BNE     OPENPICTURE_DONE                | YES, RETURN NIL AND QUIT

| _DisposHandle ;YES, Discard test handle

|
| If clipRgn = wideOpen, then SetClip(picFrame);
|
        JSR     HidePen(PC)                     | NO, TURN OFF DRAWING

| CLIPOK
|
| ALLOCATE PICSAVE RECORD
|
        MOVE.L  #500,D0                         | GET BYTE COUNT
        _NewHandle                              | ALLOCATE PIC DATA HANDLE
        BNE     OPENPICTURE_DONE                | NO, RETURN NIL AND QUIT
        _DisposeHandle                          | DISCARD TEMP HANDLE
        MOVEQ.L #0x62,D0                        | GET BYTE COUNT
        _NewHandle                              | ALLOCATE PICSAVE RECORD

        MOVE.L  A0,A4                           | GET RESULT HANDLE
        MOVE.L  A4,PICSAVE(A3)                  | SAVE RESULT IN THEPORT

|
| ALLOCATE PICCLIPRGN (leave on stack for now)
|
        CLR.L   -(SP)                           | MAKE ROOM FOR FCN RESULT
        JSR     NewRgn(PC)                      | ALLOCATE A NEW REGION

|
| ALLOCATE THEPIC PICHANDLE
|
        MOVE.L  #256,D0                         | BYTE COUNT = 256
        _NewHandle                              | ALLOCATE NEWHANDLE(256)

        MOVE.L  A0,A1                           | GET THEPIC HANDLE
        MOVE.L  A1,0xC(A6)                      | PUT HANDLE IN FCN RESULT

|
| NOW FILL THEPIC'S PICSIZE AND PICFRAME
|
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE HANDLE
        MOVE.L  A1,(A4)+                        | SAVE PICHANDLE IN THEPIC
        MOVE.L  (A1),A1                         | DE-REFERENCE PICHANDLE
        MOVE    #10,(A1)+                       | INSTALL PICSIZE = 10
        MOVE.L  0x8(A6),A0                      | POINT TO PICFRAME PARAM
        MOVE.L  (A0)+,(A1)+                     | COPY RECT INTO PICTURE
        MOVE.L  (A0)+,(A1)+                     | COPY DATA

|
| INIT STATE VARIABLES FOR PICTURE CAPTURE
|
        MOVE.L  #256,(A4)+                      | PICMAX := 256;

        MOVE.L  #10,(A4)+                       | PICINDEX := 10
        MOVE.L  (SP)+,(A4)+                     | INSTALL PICCLIPRGN
        CLR.L   (A4)+                           | PICBKPAT := WHITE
        CLR.L   (A4)+                           | CLEAR DATA
        CLR.L   (A4)+                           | PICTXFONT = 0, PICTXFACE = []
        MOVE    #1,(A4)+                        | PICTXMODE := SRCCOPY
        CLR     (A4)+                           | PICTXSIZE := 0
        CLR.L   (A4)+                           | PICSPEXTRA := 0.0
        MOVE.L  #0x10001,D0                     | GET (1,1)
        MOVE.L  D0,(A4)+                        | PICTXNUMER := (1,1)
        MOVE.L  D0,(A4)+                        | PICTXDENOM := (1,1)
        CLR.L   (A4)+                           | PICTXLOC := (0,0)
        CLR.L   (A4)+                           | PICPNLOC := (0,0)
        MOVE.L  D0,(A4)+                        | PICPNSIZE := (1,1)
        MOVE    #8,(A4)+                        | PICPNMODE := PATCOPY
        MOVEQ   #-1,D0                          | GET SOME BLACK
        MOVE.L  D0,(A4)+                        | PICPNPAT := BLACK
        MOVE.L  D0,(A4)+                        | COPY DATA
        MOVE.L  D0,(A4)+                        | PICFILLPAT := BLACK
        MOVE.L  D0,(A4)+                        | COPY DATA
        CLR.L   (A4)+                           | PICTHERECT := (0,0,0,0)
        CLR.L   (A4)+                           | CLEAR DATA
        CLR.L   (A4)+                           | PICOVSIZE := (0,0)
        MOVE.L  PORTRECT(A3),(A4)+              | PICORIGIN := CURRENT ORIGIN
        MOVE.L  #0x21,(A4)+                     | PICFGCOLOR := blackColor
        MOVE.L  #0x1E,(A4)+                     | PICBKCOLOR := whiteColor
        MOVE    #0x1101,-(SP)                   | VERSION OPCODE + VERSION 1

|
| put version number opcode
|
        JSR     PutPicWord(PC)                  | PUT TO PICTURE
OPENPICTURE_DONE:
        MOVEM.L (SP)+,A3-A4                     | DONE: RESTORE REGS
        UNLK    A6                              | RESTORE STACK FRAME
        MOVE.L  (SP)+,(SP)                      | STRIP PARAMETERS BUT KEEP RETURN ADDRESS
        RTS                                     | RETURN TO CALLER

| .PROC ClosePicture,0
| .REF PutPicByte,ShowPen,SetSize
| ------------------------------------------------------------------
|
| PROCEDURE ClosePicture;
|
ClosePicture:
        MOVEM.L D6-D7/A3,-(SP)                  | SAVE REGS
        MOVE.L  (A5),A3                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A3),A3                         | GET CURRENT GRAFPORT
        MOVE.L  PICSAVE(A3),D7                  | ARE WE SAVING A PICTURE ?
        BEQ.B   CLOSEPICTURE_GOHOME             | NO, OOPS, EXIT
        ST      -(SP)                           | YES, PUSH ENDPIC OPCODE, $FF
        JSR     PutPicByte(PC)                  | PUT TO THEPIC
        MOVE.L  D7,A0                           | GET HANDLE TO PICSAVE RECORD
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        MOVE.L  PICCLIPRGN(A0),D6               | GET picClipRgn
        MOVE.L  PICINDEX(A0),D0                 | DID PICTURE OVERFLOW ?
        BEQ.B   OVERFLO                         | YES, CONTINUE
        MOVE.L  (A0),A0                         | DEREFERENCE HANDLE
        _SetHandleSize                          | AND TRIM TO FINAL SIZE
OVERFLO:
        MOVE.L  D6,A0                           | GET PICCLIPRGN
        _DisposeHandle                          | DISCARD PICCLIPRGN

| _DisposHandle ;DISCARD IT
        MOVE.L  D7,A0                           | GET PICSAVE HANDLE
        _DisposeHandle                          | DISCARD PICSAVE
        CLR.L   PICSAVE(A3)                     | RESET PICSAVE TO NIL
        JSR     ShowPen(PC)                     | RESTORE DRAWING
CLOSEPICTURE_GOHOME:
        MOVEM.L (SP)+,D6-D7/A3                  | GOHOME: RESTORE REGS
        RTS                                     | RETURN TO CALLER

| RTS ;AND RETURN
| .PROC KillPicture
| ---------------------------------------------------
|
| PROCEDURE KillPicture(myPicture: PicHandle);
|
KillPicture:
        MOVE.L  (SP)+,A1                        | pop return addr
        MOVE.L  (SP)+,A0                        | pop handle
        _DisposeHandle                          | DISCARD PICHANDLE

| _DisposHandle ;discard it
        JMP     (A1)                            | and return

| .PROC DrawPicture,2
| .REF PicItem,NewRgn
| ------------------------------------------------------------------
|
| PROCEDURE DrawPicture(myPicture: PicHandle; dstRect: Rect);
|
DrawPicture:
        LINK    A6,#-0xA0                       | ALLOCATE LOCALS

| --------------------------------------------
|
| OFFSETS WITHIN A PICTURE PLAY STATE RECORD:
|
.set THERECT, 0                                 | RECT
.set PENLOC, THERECT+8                          | POINT
.set TEXTLOC, PENLOC+4                          | POINT
.set OVALSIZE, TEXTLOC+4                        | POINT
.set FROMRECT, OVALSIZE+4                       | RECT
.set TORECT, FROMRECT+8                         | RECT
.set NUMER, TORECT+8                            | POINT
.set DENOM, NUMER+4                             | POINT
.set THECLIP, DENOM+4                           | RGNHANDLE
.set USERCLIP, THECLIP+4                        | RGNHANDLE
.set PLAYREC, USERCLIP+4                        | TOTAL SIZE

|
| A6 OFFSETS OF PARAMS AND LOCALS AFTER LINK:
|
.set PARAMSIZE, 8                               | TOTAL BYTES OF PARAMS
.set MYPICTURE, PARAMSIZE+8-4                   | LONG, PICHANDLE
.set DSTRECT, MYPICTURE-4                       | LONG, ADDR OF RECT

.set PLAYSTATE, -PLAYREC                        | PICTURE PLAY STATE RECORD
.set SAVEPORT, PLAYSTATE-PORTREC                | GRAFPORT RECORD
.set VARSIZE, SAVEPORT                          | TOTAL BYTES OF LOCALS

        MOVEM.L D3-D7/A2-A4,-(SP)               | SAVE REGISTERS
        MOVE.L  (A5),A4                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A4),A3                         | GET CURRENT GRAFPORT
        TST.L   0xC(A6)                         | IS PICHANDLE NIL ?
        BEQ     DRAWPICTURE_GOHOME              | YES, QUIT

| --------------------------------------------------
|
| SET UP NUMER AND QUIT IF DSTRECT WIDTH OR HEIGHT IS <= 0
| COPY DSTRECT INTO TORECT
|
        MOVE.L  0x8(A6),A0                      | POINT TO DSTRECT

| --------------------------------------------------
|
        MOVE    RIGHT(A0),D0                    | GET RIGHT COORD
        SUB     LEFT(A0),D0                     | CALC DST WIDTH
        BLE     DRAWPICTURE_GOHOME              | QUIT IF WIDTH <= 0
        MOVE    D0,-0xE(A6)                     | NUMER.H := DST WIDTH
        MOVE    BOTTOM(A0),D0                   | GET BOTTOM COORD
        SUB     (A0),D0                         | CALC DST HEIGHT
        BLE     DRAWPICTURE_GOHOME              | QUIT IF HEIGHT <= 0
        MOVE    D0,-0x10(A6)                    | NUMER.V := DST HEIGHT
        LEA.L   -0x18(A6),A1                    | POINT TO LOCAL RECT
        MOVE.L  (A0)+,(A1)+                     | COPY DATA
        MOVE.L  (A0)+,(A1)+                     | TORECT := DSTRECT

| --------------------------------------------------
|
| SET UP DENOM AND QUIT IF PICFRAME WIDTH OR HEIGHT IS <= 0
| COPY PICFRAME INTO FROMRECT.
|
        MOVE.L  0xC(A6),A0                      | GET PICHANDLE

| --------------------------------------------------
|
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        LEA.L   PICFRAME(A0),A0                 | POINT TO PICTURE FRAME
        MOVE    RIGHT(A0),D0                    | GET RIGHT COORD
        SUB     LEFT(A0),D0                     | CALC SRC WIDTH
        BLE     DRAWPICTURE_GOHOME              | QUIT IF WIDTH <= 0
        MOVE    D0,-0xA(A6)                     | DENOM.H := SRC WIDTH
        MOVE    BOTTOM(A0),D0                   | GET BOTTOM COORD
        SUB     (A0),D0                         | CALC SRC HEIGHT
        BLE     DRAWPICTURE_GOHOME              | QUIT IF HEIGHT <= 0
        MOVE    D0,-0xC(A6)                     | DENOM.V := SRC HEIGHT
        LEA.L   -0x20(A6),A1                    | POINT TO FROMRECT
        MOVE.L  (A0)+,(A1)+                     | COPY DATA
        MOVE.L  (A0)+,(A1)+                     | FROMRECT := PICFRAME

| ---------------------------------------------------
|
| PRESERVE THE CURRENT GRAFPORT IN SAVEPORT
|
        MOVE.L  A3,A0                           | SRC = THEPORT
        LEA.L   -0xA0(A6),A1                    | DST = SAVEPORT
        MOVEQ.L #0x35,D0                        | PUT OPCODE IN D0
DRAWPICTURE_LOOP:
        MOVE    (A0)+,(A1)+                     | INIT DBRA COUNT
        DBF     D0,DRAWPICTURE_LOOP             | LOOP ENTIRE PORT

| ----------------------------------------
|
| INIT GLOBAL VARS:
|
        CLR.L   PATALIGN(A4)                    | PATALIGN := (0,0)
        MOVE.L  0xC(A6),PLAYPIC(A4)             | SAVE PICTURE FOR STDGETPIC
        MOVE.L  #0xA,-0xB4(A4)                  | INIT INDEX TO FIRST OPCODE


| ----------------------------------------
|
| INIT PLAY STATE RECORD:
|
        LEA.L   -0x34(A6),A0                    | POINT TO LOCAL BUFFER

| ----------------------------------------
|
        CLR.L   (A0)+                           | THERECT := (0,0,0,0)
        CLR.L   (A0)+                           | CLEAR LOCAL BUFFER
        CLR.L   (A0)+                           | PENLOC := (0,0)
        CLR.L   (A0)+                           | TEXTLOC := (0,0)
        CLR.L   (A0)+                           | OVALSIZE := (0,0)
        MOVE.L  CLIPRGN(A3),-0x4(A6)            | SAVE USER CLIPRGN

| FROMRECT SET UP
| TORECT SET UP
| NUMER SET UP
| DENOM SET UP
        CLR.L   -(SP)                           | ALLOCATE SPACE FOR RESULT
        JSR     NewRgn(PC)                      | ALLOCATE A NEW REGION
        MOVE.L  (SP)+,-0x8(A6)                  | ALLOCATE THECLIP

| --------------------------------------------------------
|
| INIT MOST FIELDS OF THEPORT
|
        CLR.L   -(SP)                           | ALLOCATE SPACE FOR RESULT
        JSR     NewRgn(PC)                      | ALLOCATE A NEW REGION
        MOVE.L  (SP)+,CLIPRGN(A3)               | ALLOCATE TEMP CLIPRGN
        LEA.L   BKPAT(A3),A0                    | POINT TO BKPAT
        CLR.L   (A0)+                           | BKPAT := WHITE
        CLR.L   (A0)+                           | CLEAR LOCAL BUFFER
        MOVEQ   #-1,D0                          | GET SOME BLACK
        MOVE.L  D0,(A0)+                        | fillPat := BLACK
        MOVE.L  D0,(A0)+                        | COPY DATA
        CLR.L   (A0)+                           | PNLOC := (0,0)
        MOVE.L  #0x10001,D1                     | SET REGION SIZE TO 10 BYTES
        MOVE.L  D1,(A0)+                        | pnSize := (1,1)
        MOVE    #8,(A0)+                        | pnMode := patCopy
        MOVE.L  D0,(A0)+                        | pnPat := black
        MOVE.L  D0,(A0)+                        | COPY DATA
        ADDQ.W  #0x2,A0                         | skip over pnVis
        CLR.L   (A0)+                           | txFont, txFace := 0
        MOVE    #1,(A0)+                        | txMode := srcOr
        CLR     (A0)+                           | txSize := 0;
        CLR.L   (A0)+                           | spExtra := 0.0;
        MOVE.L  #0x21,(A0)+                     | FGCOLOR := blackColor
        MOVE.L  #0x1E,(A0)+                     | BKCOLOR := whiteColor

| LEAVE COLRBIT ALONE
| LEAVE PATSTRETCH ALONE
| LEAVE PICSAVE ALONE
| LEAVE RGNSAVE ALONE
| LEAVE POLYSAVE ALONE
| LEAVE GRAFPROCS ALONE

| ---------------------------------------------------
|
| NOW DRAW THE PICTURE:
| REPEAT UNTIL NOT PicItem(playState);
|
MORE:
        CLR.B   -(SP)                           | MAKE ROOM FOR FCN RESULT
        PEA.L   -0x34(A6)                       | PUSH ADDR OF PLAYSTATE
        JSR     PicItem(PC)                     | DRAW ONE PICTURE ITEM
        MOVE.B  (SP)+,D0                        | POP BOOLEAN RESULT
        BNE.B   MORE                            | LOOP TILL FALSE
        MOVE.L  -0x8(A6),A0                     | GET REGION HANDLE
        _DisposeHandle                          | DISCARD TEMP REGION

| -----------------------------------------------------
|
| DISCARD HANDLES, RESTORE GRAFPORT STATE AND QUIT
|
| _DisposHandle ;DISCARD IT
        MOVE.L  CLIPRGN(A3),A0                  | GET TEMPCLIP
        _DisposeHandle                          | DISCARD TEMPCLIP
        LEA.L   -0xA0(A6),A0                    | SRC = SAVEPORT
        MOVEQ.L #0x35,D0                        | PUT OPCODE IN D0
MORE_LOOP:
        MOVE    (A0)+,(A3)+                     | INIT DBRA COUNT

| _DisposHandle ;DISCARD IT
        DBF     D0,MORE_LOOP                    | LOOP ENTIRE PORT
        CLR.L   PATALIGN(A4)                    | RESTORE PATALIGN TO (0,0)
        CLR.L   PLAYPIC(A4)                     | SET PLAYPIC TO NIL
        CLR.L   PLAYINDEX(A4)                   | AND PLAYINDEX TO 0
DRAWPICTURE_GOHOME:
        MOVEM.L (SP)+,D3-D7/A2-A4               | GOHOME: RESTORE REGISTERS
        UNLK    A6                              | RESTORE STACK FRAME
        MOVE.L  (SP)+,A0                        | GET RETURN ADDRESS
        ADDQ.W  #0x8,SP                         | POP PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER

| .FUNC PicItem,1
| .REF GetPicData,ScalePt,MapPt,MapRect,MapRgn,MapPoly
| .REF NewRgn,CopyRgn,SectRgn,UnpackBits
| .REF StdText,StdLine,StdRect,StdRRect,StdOval
| .REF StdArc,StdPoly,StdRgn,StdBits,StdComment
| ------------------------------------------------------------------
|
| FUNCTION PicItem(VAR playState: PicPlayRec): BOOLEAN;
|
| Draws one picture item, updating playState and thePort.
| Returns FALSE when an endPic opCode is encountered.
| The only state modified other than thePort and playState is patAlign.
|
PicItem:
        LINK    A6,#-0x138                      | ALLOCATE LOCALS

| --------------------------------------------
|
| OFFSETS WITHIN A PICTURE PLAY STATE RECORD:
|
.set THERECT, 0                                 | RECT
.set PENLOC, THERECT+8                          | POINT
.set TEXTLOC, PENLOC+4                          | POINT
.set OVALSIZE, TEXTLOC+4                        | POINT
.set FROMRECT, OVALSIZE+4                       | RECT
.set TORECT, FROMRECT+8                         | RECT
.set NUMER, TORECT+8                            | POINT
.set DENOM, NUMER+4                             | POINT
.set THECLIP, DENOM+4                           | RGNHANDLE
.set USERCLIP, THECLIP+4                        | RGNHANDLE
.set PLAYREC, USERCLIP+4                        | TOTAL SIZE

|
| params:
|
.set PARAMSIZE, 4                               | TOTAL BYTES OF PARAMS
.set RESULT, PARAMSIZE+8                        | BOOLEAN
.set PLAYSTATE, RESULT-4                        | LONG, PICHANDLE

|
| locals:
|
.set HANDLE1, -4                                | HANDLE
.set HANDLE2, HANDLE1-4                         | HANDLE
.set DSTRECT, HANDLE2-8                         | RECT
.set SRCRECT, DSTRECT-8                         | RECT
.set SRCBITS, SRCRECT-14                        | BITMAP, MUST BE BELOW SRCRECT
.set SAMEFLAG, SRCBITS-2                        | BOOLEAN
.set NEWPT, SAMEFLAG-4                          | LONG
.set TXDATA, NEWPT-256                          | UP TO 256 CHARACTERS,

| ;ALSO USED FOR PACKBUF !!!
.set SRCPTR, TXDATA-4                           | LONG
.set DSTPTR, SRCPTR-4                           | LONG
.set SAVESP, DSTPTR-4                           | LONG
.set VARSIZE, SAVESP                            | TOTAL BYTES OF LOCALS

        MOVEM.L D3-D7/A2-A4,-(SP)               | SAVE REGISTERS
        MOVE.L  A7,-0x138(A6)                   | REMEMBER STACK FOR ABORT
        MOVE.L  (A5),A4                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A4),A3                         | GET CURRENT GRAFPORT

|
| GET PICTURE OPCODE AND CHECK FOR END OF PICTURE.
|
        BSR     GETUBYTE                        | GET OPCODE BYTE
        MOVE    D0,D7                           | PUT IT IN D7
        CMPI.B  #0xFF,D7                        | IS THIS THE PICEND OPCODE ?
        BNE.B   NOTEND                          | NO, CONTINUE
        CLR.B   0xC(A6)                         | YES, RETURN FALSE
        BRA     KILL1_EXIT                      | AND QUIT

| ----------------------------------------------------------
|
| NOTEND
|
NOTEND:
        MOVE.B  #0x1,0xC(A6)                    | RETURN TRUE
        CMPI    #0x20,D7                        | IS IT A PARAM OPCODE ?
        BCS.B   NOTEND_OK                       | YES, GO TO IT

|
| CHECK FOR PARAM OPCODES $00..$1F
|

|
| GET LO AND HI NIBBLES OF OPCODE, AND CASE ON HI NIBBLE (NOUN).
        MOVE.B  D7,D0                           | COPY OPCODE
        ANDI    #0xF0,D0                        | MASK FOR HI NIBBLE
        BTST    #3,D7                           | IS OPCODE BIT 3 SET ?
        SNE.B   -0x28(A6)                       | REMEMBER IN SAMEFLAG
        ANDI    #0x7,D7                         | GET VERB FROM LO NIBBLE
        LSR     #3,D0                           | DOUBLE HI NIBBLE FOR INDEX
        MOVE    NOTEND_CONT(PC,D0.W),D0         | GET JUMP OFFSET
        JMP     NOTEND_CONT(PC,D0.W)            | TAKE CASE JUMP

| ----------------------------------------------------------
|
| NOTEND_CONT
|
NOTEND_CONT:
  .byte 0x06,0x0A,0x06,0x0A,0x01,0xB2           | OFFSETS FOR OPCODES 0-2
  .byte 0x02,0xB8,0x02,0xD2,0x02,0xF4           | OFFSETS FOR OPCODES 3-5
  .byte 0x03,0x0E,0x03,0x34,0x03,0x66           | OFFSETS FOR OPCODES 6-8
  .byte 0x03,0x98,0x04,0x6E,0x06,0x0A           | OFFSETS FOR OPCODES 9-11
  .byte 0x06,0x0A,0x06,0x0A,0x06,0x0A           | OFFSETS FOR OPCODES 12-14
  .byte 0x06,0x0A,0x06,0x0A                     | OFFSETS FOR OPCODES 15-16
NOTEND_OK:
        ANDI    #0x1F,D7                        | MASK OUT PARAM OPCODE

| ---------------------------------------------------
|
| OPCODES $00..$1F DO NO DRAWING, THEY JUST SET PARAMETERS.
|
        ADD     D7,D7                           | DOUBLE PARAM FOR CASE INDEX
        MOVE    NOTEND_CONT_2(PC,D7.W),D0       | GET CASE JUMP OFFSET
        JMP     NOTEND_CONT_2(PC,D0.W)          | TAKE CASE JUMP

| ----------------------------------------------------------
|
| NOTEND_CONT_2
|
NOTEND_CONT_2:
  .byte 0x05,0xDA,0x00,0x40,0x00,0x9E           | PLAY OFFSETS: OPCODES 0-2
  .byte 0x00,0xA4,0x00,0xAA,0x00,0xB4           | PLAY OFFSETS: OPCODES 3-5
  .byte 0x00,0xC0,0x00,0xC6,0x01,0x16           | PLAY OFFSETS: OPCODES 6-8
  .byte 0x01,0x1E,0x01,0x26,0x01,0x2E           | PLAY OFFSETS: OPCODES 9-11
  .byte 0x01,0x4E,0x00,0xBA,0x00,0x92           | PLAY OFFSETS: OPCODES 12-14
  .byte 0x00,0x98,0x00,0xE6,0x01,0x0E           | PLAY OFFSETS: OPCODES 15-17
  .byte 0x05,0xDA,0x05,0xDA,0x05,0xDA           | PLAY OFFSETS: OPCODES 18-20
  .byte 0x05,0xDA,0x05,0xDA,0x05,0xDA           | PLAY OFFSETS: OPCODES 21-23
  .byte 0x05,0xDA,0x05,0xDA,0x05,0xDA           | PLAY OFFSETS: OPCODES 24-26
  .byte 0x05,0xDA,0x05,0xDA,0x05,0xDA           | PLAY OFFSETS: OPCODES 27-29
  .byte 0x05,0xDA,0x05,0xDA                     | PLAY OFFSETS: OPCODES 30-31

NOTEND_CONT_3:
        BSR     SAME1_CONT                      | COPY RGN INTO HANDLE1
        MOVE.L  0x8(A6),A2                      | POINT TO PLAYSTATE RECORD
        MOVE.L  -0x4(A6),-(SP)                  | PUSH HANDLE1
        MOVE.L  0x2C(A2),-(SP)                  | PUSH PLAYSTATE THECLIP
XCLIP2:
        JSR     CopyRgn(PC)                     | COPY HANDLE1 INTO THECLIP
        MOVE.L  0x8(A6),A2                      | POINT TO PLAYSTATE RECORD
        MOVE.L  -0x4(A6),-(SP)                  | PUSH HANDLE1 TEMP
        PEA.L   0x14(A2)                        | PUSH FROMRECT
        PEA.L   0x1C(A2)                        | PUSH TORECT
        JSR     MapRgn(PC)                      | MAP RGN INTO DST COORDS
        MOVE.L  0x8(A6),A2                      | POINT TO PLAYSTATE RECORD
        MOVE.L  -0x4(A6),-(SP)                  | PUSH MAPPED RGN
        MOVE.L  0x30(A2),-(SP)                  | PUSH ORIGINAL CLIP
        MOVE.L  CLIPRGN(A3),-(SP)               | PUSH DST = THEPORT^.CLIPRGN
        JSR     SectRgn(PC)                     | PUT INTERSECT INTO CLIPRGN
        BRA     KILL1                           | DISCARD HANDLE1 AND QUIT

| ----------------------------------------------------------
|
| GET8
|
GET8:
        MOVEQ   #8,D6                           | BYTECOUNT = 8
        BRA     GETDONE                         | COPY 8 BYTES AND QUIT

| ----------------------------------------------------------
|
| GET4
|
GET4:
        MOVEQ   #4,D6                           | BYTECOUNT = 4
        BRA     GETDONE                         | COPY 4 BYTES AND QUIT

| ----------------------------------------------------------
|
| GET2
|
GET2:
        MOVEQ   #2,D6                           | BYTECOUNT = 2
        BRA     GETDONE                         | COPY 2 BYTES AND QUIT

| ----------------------------------------------------------
|
| GET2_CONT
|
GET2_CONT:
        LEA.L   FGCOLOR(A3),A3                  | POINT TO FOREGROUND COLOR
        BRA.B   GET4                            | GET FOREGROUND COLOR

| ----------------------------------------------------------
|
| GET2_CONT_2
|
GET2_CONT_2:
        LEA.L   BKCOLOR(A3),A3                  | POINT TO BACKGROUND COLOR
        BRA.B   GET4                            | GET BACKGROUND COLOR

| ----------------------------------------------------------
|
| GET2_CONT_3
|
GET2_CONT_3:
        LEA.L   BKPAT(A3),A3                    | POINT TO BACKGROUND PATTERN
        BRA.B   GET8                            | GET BKPAT

| ----------------------------------------------------------
|
| GET2_CONT_4
|
GET2_CONT_4:
        LEA.L   TXFONT(A3),A3                   | POINT TO TEXT FONT
        BRA.B   GET2                            | GET TXFONT

| ----------------------------------------------------------
|
| GET2_CONT_5
|
GET2_CONT_5:
        LEA.L   TXFACE(A3),A3                   | POINT TO TEXT FACE
        MOVEQ   #1,D6                           | SIZE IS 1 WORD
        BRA     GETDONE                         | GET TXFACE

| ----------------------------------------------------------
|
| GET2_CONT_6
|
GET2_CONT_6:
        LEA.L   TXMODE(A3),A3                   | POINT TO TEXT MODE
        BRA.B   GET2                            | GET TXMODE

| ----------------------------------------------------------
|
| GET2_CONT_7
|
GET2_CONT_7:
        LEA.L   TXSIZE(A3),A3                   | POINT TO TEXT SIZE
        BRA.B   GET2                            | GET TXSIZE

| ----------------------------------------------------------
|
| GET2_CONT_8
|
GET2_CONT_8:
        LEA.L   SPEXTRA(A3),A3                  | POINT TO SPEXTRA
        BRA.B   GET4                            | GET fixed point SPACE EXTRA

| ----------------------------------------------------------
|
| GET2_CONT_9
|
GET2_CONT_9:
        JSR     GETWORD_NO(PC)                  | GET PNSIZE
        MOVE.L  D0,PNSIZE(A3)                   | INSTALL INTO THEPORT
        PEA.L   PNSIZE(A3)                      | PUSH PEN SIZE
        MOVE.L  0x8(A6),A2                      | POINT TO PLAYSTATE RECORD
        PEA.L   0x14(A2)                        | PUSH SOURCE RECT
        PEA.L   0x1C(A2)                        | PUSH DEST RECT
        JSR     ScalePt(PC)                     | SCALE PNSIZE
        BRA     KILL1_EXIT                      | GO TO COMMON SCALING

| ----------------------------------------------------------
|
| GET2_CONT_10
|
GET2_CONT_10:
        MOVE.L  0x8(A6),A3                      | POINT TO PLAYSTATE RECORD
        JSR     GETWORD_NO(PC)                  | GET TEXT NUMER
        MOVE.L  D0,0x24(A3)                     | INSTALL INTO PLAYSTATE
        JSR     GETWORD_NO(PC)                  | GET TEXT DENOM
        MOVE.L  D0,FILLPAT(A3)                  | INSTALL INTO PLAYSTATE
        PEA.L   0x24(A3)                        | PUSH PORT RECT
        PEA.L   0x14(A3)                        | PUSH PORT BOUNDS
        PEA.L   CLIPRGN(A3)                     | PUSH CLIP REGION
        JSR     ScalePt(PC)                     | SCALE NUMER
        BRA     KILL1_EXIT                      | GO TO COMMON SCALING

| ----------------------------------------------------------
|
| GET2_CONT_11
|
GET2_CONT_11:
        BSR     GETUBYTE                        | GET VERSION NUMBER BYTE
        BRA     KILL1_EXIT                      | AND IGNORE IT

| ----------------------------------------------------------
|
| GET2_CONT_12
|
GET2_CONT_12:
        LEA.L   PNMODE(A3),A3                   | POINT TO PEN MODE
        BRA     GET2                            | GET PNMODE

| ----------------------------------------------------------
|
| GET2_CONT_13
|
GET2_CONT_13:
        LEA.L   PNPAT(A3),A3                    | POINT TO PEN PATTERN
        BRA     GET8                            | GET PNPAT

| ----------------------------------------------------------
|
| GET2_CONT_14
|
GET2_CONT_14:
        LEA.L   FILLPAT(A3),A3                  | POINT TO FILL PATTERN
        BRA     GET8                            | GET FILLPAT

| ----------------------------------------------------------
|
| GET2_CONT_15
|
GET2_CONT_15:
        JSR     GETWORD_NO(PC)                  | GET OVAL SIZE
        MOVE.L  0x8(A6),A2                      | POINT TO PLAYSTATE RECORD
        MOVE.L  D0,0x10(A2)                     | SAVE NEW POINT
        PEA.L   0x10(A2)                        | PUSH NEW POINT
        PEA.L   0x14(A2)                        | PUSH SOURCE RECT
        PEA.L   0x1C(A2)                        | PUSH DEST RECT
        JSR     ScalePt(PC)                     | SCALE OVAL SIZE
        BRA     KILL1_EXIT                      | GO TO COMMON SCALING

| -----------------------------------------------------
|
| CHANGE ORIGIN: ADD DH AND DV TO FROMRECT, ADJUST PATALIGN,
| THEN RE-MAP THECLIP
|
GET2_CONT_16:
        JSR     GETWORD_NO(PC)                  | GET DH,DV
        MOVE.L  0x8(A6),A2                      | POINT TO PLAYSTATE RECORD
        ADD     D0,0x14(A2)                     | ADD DV TO FROMRECT
        ADD     D0,0x18(A2)                     | ADJUST RECT LEFT
        ADD     D0,-0xA8(A4)                    | AND TO PATALIGN
        SWAP    D0                              | GET DH IN LO WORD
        ADD     D0,0x16(A2)                     | ADD DH TO FROMRECT
        ADD     D0,0x1A(A2)                     | ADJUST RECT RIGHT
        ADD     D0,-0xA6(A4)                    | AND TO PATALIGN

|
| RE-COMPUTE MAPPED CLIPRGN FROM UNMAPPED THECLIP
|
        MOVE.L  0x2C(A2),-(SP)                  | PUSH THECLIP

        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        JSR     NewRgn(PC)                      | ALLOCATE A TEMP RGN
        MOVE.L  (SP),-0x4(A6)                   | PUT IN HANDLE1
        BRA     XCLIP2                          | COPY, MAP, SectScan, AND DISCARD

| ---------------------------------------------------
|
| TEXT OR LINE OPCODES:
|
| LINE: 20, PNLOC(pt), NEWPT(pt)
| LINEFROM: 21, NEWPT(pt)
| SHORT LINE: 22, PNLOC(pt), DH(byte), DV(byte)
| SHORTLNFROM: 23, DH(byte), DV(byte)
|
| TEXT: 28,29,2A,2B
|
GET2_CONT_17:
        TST.B   -0x28(A6)                       | IS THIS A TEXT OPCODE ?

| ---------------------------------------------------
|
        BNE     TEXTOP                          | YES, DO IT
        MOVE.L  0x8(A6),A2                      | POINT TO PLAYSTATE RECORD
        MOVE.L  0x8(A2),D0                      | NO, GET PREVIOUS LINE ENDPOINT
        ROR     #1,D7                           | IS LO NIBBLE ODD ? (BIT 0)
        BCS.B   LNFROM                          | YES, DRAW LINE FROM PREV
        BSR     GETWORD_NO                      | NO, GET NEW STARTPT
LNFROM:
        MOVE.L  D0,PNLOC(A3)                    | COPY STARTPT INTO THEPORT
        MOVE.L  D0,-0x2C(A6)                    | SAVE FOR SHORT DH,DV BELOW
        MOVE.L  0x8(A6),A2                      | POINT TO PLAYSTATE RECORD
        PEA.L   PNLOC(A3)                       | PUSH PEN LOCATION
        PEA.L   0x14(A2)                        | PUSH SOURCE RECT
        PEA.L   0x1C(A2)                        | PUSH DEST RECT
        JSR     MapPt(PC)                       | MAP STARTPT
        ROR     #1,D7                           | IS OPCODE BIT 1 SET ?
        BCS.B   SHORTLN                         | YES, USE SHORT DH,DV FORM
        BSR     GETWORD_NO                      | NO, GET NEWPT
        MOVE.L  D0,-0x2C(A6)                    | PUT IN TEMP
        BRA.B   LNOK                            | AND CONTINUE

| ----------------------------------------------------------
|
| SHORTLN
|
SHORTLN:
        BSR     GETSBYTE                        | GET A SIGNED BYTE
        ADD     D0,-0x2A(A6)                    | ADD TO STARTPT.H
        BSR     GETSBYTE                        | GET A SIGNED BYTE
        ADD     D0,-0x2C(A6)                    | ADD TO STARTPT.V
LNOK:
        MOVE.L  0x8(A6),A2                      | POINT TO PLAYSTATE RECORD
        MOVE.L  -0x2C(A6),0x8(A2)               | REMEMBER NEWPT FOR NEXT TIME
        PEA.L   -0x2C(A6)                       | PUSH ADDRESS OF NEWPT
        PEA.L   0x14(A2)                        | PUSH SOURCE RECT
        PEA.L   0x1C(A2)                        | PUSH DEST RECT
        JSR     MapPt(PC)                       | MAP NEWPT
        MOVE.L  -0x2C(A6),-(SP)                 | PUSH NEWPT PARAM FOR LINEPROC
        MOVE.L  (0xE40).w,A0                    | _StdLine (lineProc)
        MOVE.L  GRAFPROCS(A3),D0                | IS GRAFPROCS NIL ?
        BEQ.B   LNOK_OK                         | YES, USE STD PROC
        MOVE.L  D0,A0                           | COPY POINTER
        MOVE.L  LINEPROC(A0),A0                 | NO, GET PROCPTR
LNOK_OK:
        BRA     CALL0                           | CALL NO-ARGUMENT ROUTINE

| ----------------------------------------------------------
|
| TEXTOP
|
TEXTOP:
        ANDI    #0x3,D7                         | MASK TO 2 BITS

| ---------------------------------------------------
|
| LONG TEXT: 28, txLoc(pt), count(0..255), text
| DH TEXT: 29, dh(0..255), count(0..255), text
| DV TEXT: 2A, dv(0..255), count(0..255), text
| DHDV TEXT: 2B: dh(0..255), dv(0,..255), count(0..255), text
|
        BEQ.B   LONGTXT                         | YES, USE LONG FORMAT
        ROR     #1,D7                           | DO WE NEED DH ? (BIT 0)
        BCC.B   PICITEM_DHOK                    | NO, CONTINUE
        BSR     GETUBYTE                        | GET DH 0..255
        MOVE.L  0x8(A6),A2                      | POINT TO PLAYSTATE RECORD
        ADD     D0,0xE(A2)                      | BUMP TEXTLOC.H
PICITEM_DHOK:
        ROR     #1,D7                           | DHOK: DO WE NEED DV ? (BIT 1)
        BCC.B   TEXTOP2                         | NO, CONTINUE
        BSR     GETUBYTE                        | GET DV 0..255
        MOVE.L  0x8(A6),A2                      | POINT TO PLAYSTATE RECORD
        ADD     D0,0xC(A2)                      | BUMP TEXTLOC.V
        BRA.B   TEXTOP2                         | SHARE CODE

| ----------------------------------------------------------
|
| LONGTXT
|
LONGTXT:
        BSR     GETWORD_NO                      | GET TXLOC, UNMAPPED
        MOVE.L  0x8(A6),A2                      | POINT TO PLAYSTATE RECORD
        MOVE.L  D0,0xC(A2)                      | SAVE IN TEXTLOC
TEXTOP2:
        BSR     GETUBYTE                        | GET TEXT LENGTH 0..255
        MOVE    D0,D6                           | SAVE LENGTH IN D6
        PEA.L   -0x12C(A6)                      | PUSH ADDR OF TEXT BUF
        MOVE    D6,-(SP)                        | PUSH BYTECOUNT
        JSR     GetPicData(PC)                  | GET THE TEXT
        MOVE.L  0x8(A6),A2                      | POINT TO PLAYSTATE RECORD
        MOVE.L  0xC(A2),PNLOC(A3)               | COPY TEXTLOC INTO PNLOC
        PEA.L   PNLOC(A3)                       | PUSH PEN LOCATION
        PEA.L   0x14(A2)                        | PUSH SOURCE RECT
        PEA.L   0x1C(A2)                        | PUSH DEST RECT
        JSR     MapPt(PC)                       | MAP PNLOC
        MOVE    D6,-(SP)                        | PUSH CHARACTER COUNT
        PEA.L   -0x12C(A6)                      | PUSH ADDRESS OF TEXT
        MOVE.L  0x8(A6),A2                      | POINT TO PLAYSTATE RECORD
        MOVE.L  0x24(A2),-(SP)                  | PUSH NUMER
        MOVE.L  0x28(A2),-(SP)                  | PUSH DENOM
        MOVE.L  (0xE08).w,A0                    | _StdText (textProc)
        MOVE.L  GRAFPROCS(A3),D0                | IS GRAFPROCS NIL ?
        BEQ.B   TEXTOP2_OK                      | YES, USE STD PROC
        MOVE.L  D0,A0                           | COPY POINTER
        MOVE.L  (A0),A0                         | DEREFERENCE HANDLE
TEXTOP2_OK:
        BRA     CALL0                           | CALL NO-ARGUMENT ROUTINE

| ---------------------------------------------------
|
| Rect: OP, RECT
|
RECTOP:
        MOVE.B  D7,-(SP)                        | PUSH VERB
        BSR     GETRECT                         | GET AND PUSH DSTRECT
        MOVE.L  (0xE80).w,A0                    | _StdRect (rectProc)
        MOVE.L  GRAFPROCS(A3),D0                | IS GRAFPROCS NIL ?
        BEQ.B   RECTOP_OK                       | YES, USE STD PROC
        MOVE.L  D0,A0                           | COPY POINTER
        MOVE.L  RECTPROC(A0),A0                 | NO, GET PROCPTR
RECTOP_OK:
        BRA     CALL0                           | CALL NO-ARGUMENT ROUTINE

| ---------------------------------------------------
|
| RRect: OP, RECT, OVALPT
|
RRECTOP:
        MOVE.B  D7,-(SP)                        | PUSH VERB
        BSR     GETRECT                         | GET AND PUSH DSTRECT
        MOVE.L  0x8(A6),A2                      | POINT TO PLAYSTATE RECORD
        MOVE.L  0x10(A2),-(SP)                  | PUSH OVHT,OVWD
        MOVE.L  (0xEBC).w,A0                    | _StdRRect (rRectProc)
        MOVE.L  GRAFPROCS(A3),D0                | IS GRAFPROCS NIL ?
        BEQ.B   RRECTOP_OK                      | YES, USE STD PROC
        MOVE.L  D0,A0                           | COPY POINTER
        MOVE.L  RRECTPROC(A0),A0                | NO, GET PROCPTR
RRECTOP_OK:
        BRA     CALL0                           | CALL NO-ARGUMENT ROUTINE

| ---------------------------------------------------
|
| Oval: OP, RECT
|
OVALOP:
        MOVE.B  D7,-(SP)                        | PUSH VERB
        BSR     GETRECT                         | GET AND PUSH DSTRECT
        MOVE.L  (0xED8).w,A0                    | _StdOval (ovalProc)
        MOVE.L  GRAFPROCS(A3),D0                | IS GRAFPROCS NIL ?
        BEQ.B   OVALOP_OK                       | YES, USE STD PROC
        MOVE.L  D0,A0                           | COPY POINTER
        MOVE.L  OVALPROC(A0),A0                 | NO, GET PROCPTR
OVALOP_OK:
        BRA     CALL0                           | CALL NO-ARGUMENT ROUTINE

| ---------------------------------------------------
|
| Arc: OP, RECT, STARTANGLE, ARCANGLE
|
ARCOP:
        MOVE.B  D7,-(SP)                        | PUSH VERB
        BSR     GETRECT                         | GET AND PUSH DSTRECT
        BSR     GETWORD                         | GET STARTANGLE
        MOVE    D0,-(SP)                        | PUSH STARTANGLE
        BSR     GETWORD                         | GET ARCANGLE
        MOVE    D0,-(SP)                        | PUSH ARCANGLE
        MOVE.L  (0xEF4).w,A0                    | _StdArc (arcProc)
        MOVE.L  GRAFPROCS(A3),D0                | IS GRAFPROCS NIL ?
        BEQ.B   ARCOP_OK                        | YES, USE STD PROC
        MOVE.L  D0,A0                           | COPY POINTER
        MOVE.L  ARCPROC(A0),A0                  | NO, GET PROCPTR
ARCOP_OK:
        BRA     CALL0                           | CALL NO-ARGUMENT ROUTINE

| ---------------------------------------------------
|
| Poly: OP, POLY
|
POLY:
        BSR     SAME1_CONT                      | COPY POLY INTO HANDLE1
        MOVE.L  -0x4(A6),-(SP)                  | PUSH POLYHANDLE
        MOVE.L  0x8(A6),A2                      | POINT TO PLAYSTATE RECORD
        PEA.L   0x14(A2)                        | PUSH FROMRECT
        PEA.L   0x1C(A2)                        | PUSH TORECT
        JSR     MapPoly(PC)                     | MAP POLY INTO DST COORDS
        MOVE.B  D7,-(SP)                        | PUSH VERB
        MOVE.L  -0x4(A6),-(SP)                  | PUSH POLYHANDLE
        MOVE.L  (0xF14).w,A0                    | _StdPoly (polyProc)
        MOVE.L  GRAFPROCS(A3),D0                | IS GRAFPROCS NIL ?
        BEQ.B   ARCOP_OK_2                      | YES, USE STD PROC
        MOVE.L  D0,A0                           | COPY POINTER
        MOVE.L  POLYPROC(A0),A0                 | NO, GET PROCPTR
ARCOP_OK_2:
        BRA     CALL1                           | CALL ONE-ARGUMENT ROUTINE

| ---------------------------------------------------
|
| Rgn: OP, RGN
|
ARCOP_CONT:
        BSR     SAME1_CONT                      | COPY RGN INTO HANDLE1
        MOVE.L  -0x4(A6),-(SP)                  | PUSH RGN
        MOVE.L  0x8(A6),A2                      | POINT TO PLAYSTATE RECORD
        PEA.L   0x14(A2)                        | PUSH FROMRECT
        PEA.L   0x1C(A2)                        | PUSH TORECT
        JSR     MapRgn(PC)                      | MAP RGN INTO DSTRECT COORDS
        MOVE.B  D7,-(SP)                        | PUSH VERB
        MOVE.L  -0x4(A6),-(SP)                  | PUSH RGN
        MOVE.L  (0xF44).w,A0                    | _StdRgn (rgnProc)
        MOVE.L  GRAFPROCS(A3),D0                | IS GRAFPROCS NIL ?
        BEQ.B   ARCOP_OK_3                      | YES, USE STD PROC
        MOVE.L  D0,A0                           | COPY POINTER
        MOVE.L  RGNPROC(A0),A0                  | NO, GET PROCPTR
ARCOP_OK_3:
        BRA     CALL1                           | CALL ONE-ARGUMENT ROUTINE

| ----------------------------------------------------------
|
| ARCOP_CONT_2
|
ARCOP_CONT_2:
        PEA.L   -0x22(A6)                       | PUSH LOCAL RECT

| --------------------------------------------------------------------------
|
| BitsRect: 90, ROWBYTES, BOUNDS, SRCRECT, DSTRECT, MODE,
| BYTECOUNT, BITDATA,
|
| BitsRgn: 91, ROWBYTES, BOUNDS, SRCRECT, DSTRECT, MODE,
| MASKRGN, BYTECOUNT, BITDATA,
|
| PackBitsRect: 98, ROWBYTES, BOUNDS, SRCRECT, DSTRECT, MODE,
| PackBitsRgn: 99, ROWBYTES, BOUNDS, SRCRECT, DSTRECT, MODE,
        MOVE    #26,-(SP)                       | PUSH BYTECOUNT = 26
        JSR     GetPicData(PC)                  | GET ROWBYTES,BOUNDS,SRC,DST
        MOVE.L  0x8(A6),A2                      | POINT TO PLAYSTATE RECORD
        PEA.L   -0x10(A6)                       | PUSH LOCAL POINT
        PEA.L   0x14(A2)                        | PUSH SOURCE RECT
        PEA.L   0x1C(A2)                        | PUSH DEST RECT
        JSR     MapRect(PC)                     | MAP DSTRECT
        PEA.L   -0x26(A6)                       | PUSH SRCBITS
        PEA.L   -0x18(A6)                       | PUSH ADDR OF SRCRECT
        PEA.L   -0x10(A6)                       | PUSH ADDR OF DSTRECT
        BSR     GETWORD                         | GET MODE
        MOVE    D0,-(SP)                        | PUSH MODE
        TST     D7                              | IS MASKRGN USED ?
        BNE.B   USERGN                          | YES, CONTINUE
        CLR.L   -(SP)                           | NO, PUSH MASKRGN = NIL
        BRA.B   USERGN_CONT                     | AND CONTINUE

| ----------------------------------------------------------
|
| USERGN
|
USERGN:
        BSR     SAME1_CONT                      | GET MASKRGN INTO HANDLE1
        MOVE.L  -0x4(A6),-(SP)                  | PUSH MASKRGN
        MOVE.L  -0x4(A6),-0x8(A6)               | REMEMBER MASKRGN IN HANDLE2
USERGN_CONT:
        MOVE    -0x1C(A6),D6                    | REMEMBER MASKRGN IN HANDLE2
        SUB     -0x20(A6),D6                    | CALC HEIGHT
        MOVE    D6,D5                           | COPY HEIGHT
        MULU    -0x22(A6),D5                    | CALC BITMAP SIZE
        MOVE.L  D5,D0                           | GET BYTECOUNT
        _NewHandle                              | ALLOCATE BITS HANDLE
        BEQ     MEMOK                           | CONTINUE IF NOT MEMFULL
        MOVE.L  (SP)+,A0                        | POP MASKRGN (MAYBE NIL)
        _DisposeHandle                          | DISCARD MASKRGN

| _DisposHandle ;DISCARD IT
        BRA     KILL1_ERR                       | AND ABORT

| ----------------------------------------------------------
|
| MEMOK
|
MEMOK:
        _HLock                                  | LOCK HANDLE1
        MOVE.L  A0,-0x4(A6)                     | REMEMBER IN HANDLE1

|
| IF OPCODE BIT3 SET, THEN UNPACK COMPRESSED SCANLINES
|
        MOVE.L  -0x4(A6),A0                     | GET HANDLE1
        TST.B   -0x28(A6)                       | WAS BIT 3 SET ?

        BEQ.B   PICITEM_NOPACK                  | NO, IT'S NOT PACKED
        MOVE.L  (A0),-0x134(A6)                 | YES, INIT DSTPTR
        BRA.B   PICITEM_START1                  | GO TO LOOP START

| ----------------------------------------------------------
|
| PICITEM_MORE1
|
PICITEM_MORE1:
        BSR     GETUBYTE                        | GET PACKED BYTECOUNT
        PEA.L   -0x12C(A6)                      | PUSH ADDR OF BUFFER
        MOVE.L  (SP),-0x130(A6)                 | PUT IN SRCPTR TOO
        MOVE    D0,-(SP)                        | PUSH BYTECOUNT
        JSR     GetPicData(PC)                  | GET PACKED DATA
        PEA.L   -0x130(A6)                      | PUSH VAR SRCPTR
        PEA.L   -0x134(A6)                      | PUSH VAR DSTPTR
        MOVE    -0x22(A6),-(SP)                 | PUSH ROWBYTES
        JSR     UnpackBits(PC)                  | UNPACK INTO HANDLE1 DATA
PICITEM_START1:
        DBF     D6,PICITEM_MORE1                | LOOP HEIGHT ROWS
        BRA.B   DOBITS                          | CONTINUE

|
| BIT3 = 0, DONT USE PACKING
|
PICITEM_NOPACK:
        MOVE.L  (A0),-(SP)                      | NOPACK: PUSH MASTER
        MOVE    D5,-(SP)                        | PUSH BYTECOUNT
        JSR     GetPicData(PC)                  | READ BITMAP DATA BITS
DOBITS:
        MOVE.L  -0x4(A6),A0                     | GET HANDLE1
        MOVE.L  (A0),-0x26(A6)                  | SAVE DATA TO LOCAL
        MOVE.L  (0xFAC).w,A0                    | _StdBits (bitsProc)
        MOVE.L  GRAFPROCS(A3),D0                | IS GRAFPROCS NIL ?
        BEQ.B   BITSOK                          | YES, USE STD PROC
        MOVE.L  D0,A0                           | COPY POINTER
        MOVE.L  BITSPROC(A0),A0                 | NO, GET PROCPTR
BITSOK:
        JSR     (A0)                            | CALL BITSPROC
        MOVE.L  -0x4(A6),A0                     | GET HANDLE1
        _HUnlock                                | UNLOCK THE DATABITS
        TST     D7                              | IS MASKRGN USED ?
        BEQ     KILL1                           | NO, DISCARD ONLY DATABITS
        BRA     KILL2                           | DISCARD MASKRGN & DATABITS

| --------------------------------------------------------------------------
|
| CommentOp: OP, KIND, { SIZE, DATA }
|
COMMENTOP:
        BSR     GETWORD                         | GET COMMENT KIND IN D0
        MOVE    D0,-(SP)                        | PUSH FOR COMMENTPROC
        TST.B   D7                              | IS THIS SHORT FORM ?
        BNE.B   LONGCOM                         | NO, GET MORE
        CLR     -(SP)                           | YES, PUSH DATASIZE = 0
        CLR.L   -(SP)                           | PUSH DATAHANDLE = NIL
        MOVE.L  (0xFC4).w,A0                    | _StdComment (commentProc)
        MOVE.L  GRAFPROCS(A3),D0                | IS GRAFPROCS NIL ?
        BEQ.B   BITSOK_OK                       | YES, USE STD PROC
        MOVE.L  D0,A0                           | COPY POINTER
        MOVE.L  COMMENTPROC(A0),A0              | NO, GET PROCPTR
BITSOK_OK:
        BRA     CALL0                           | CALL NO-ARGUMENT ROUTINE

| ----------------------------------------------------------
|
| LONGCOM
|
LONGCOM:
        BSR     GETWORD                         | GET DATASIZE
        MOVE    D0,-(SP)                        | PUSH DATASIZE
        CLR     D4                              | INIT BYTE INDEX FOR GETHND2
        BSR     GETHND2                         | GET DATA INTO HANDLE1
        MOVE.L  -0x4(A6),-(SP)                  | PUSH DATA HANDLE
        MOVE.L  (0xFC4).w,A0                    | _StdComment (commentProc)
        MOVE.L  GRAFPROCS(A3),D0                | IS GRAFPROCS NIL ?
        BEQ.B   LONGCOM_OK                      | YES, USE STD PROC
        MOVE.L  D0,A0                           | COPY POINTER
        MOVE.L  COMMENTPROC(A0),A0              | NO, GET PROCPTR
LONGCOM_OK:
        BRA     CALL1                           | CALL ONE-ARGUMENT ROUTINE

| ----------------------------------------------------------
|
| CONTEXT
|
| Easter Egg - draws a small bitmap ("stolen from Apple Computer")
| into the screen buffer and then halts by spinning forever.
|
| Context:
| - A5 points into QuickDraw state / globals used here.
| - (A5) yields a pointer to a structure from which this
| routine fetches:
| * a destination pointer to screen memory
| * a row stride (bytes between scanlines)
| - LAYOUT contains 25 longwords = 100 bytes total.
| - Each longword is one 32-pixel-wide 1-bit scanline.
| - On the compact Mac framebuffer, 1 bits are black.
|
| Net effect:
| - Copy a 32 x 25 monochrome bitmap into the framebuffer,
| one row at a time.
| - Then loop forever so the image remains displayed.
|
CONTEXT:
| Load a base pointer from the QuickDraw-related state.
| A0 = *(uint32_t *)A5
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS

| Fetch the destination address.
| A1 = *(uint32_t *)(A0 - 0x7A)
|
| In this context, this is the target address in the
| screen buffer where the first scanline will be written.
        MOVE.L  -0x7A(A0),A1                    | GET POINTER TO DATA

| Fetch the per-row stride.
| D0 = *(int16_t *)(A0 - 0x76)
|
| This is the number of bytes to add to A1 after each
| 32-bit row write so the next write lands on the next
| scanline in the framebuffer.
        MOVE    -0x76(A0),D0                    | GET ROWBYTES

| Point A0 at the embedded bitmap data.
| A0 = &LAYOUT
        LEA.L   LAYOUT(PC),A0                   | POINT TO DATA TABLE

| Set loop counter to 24.
|
| Because DBF decrements and continues until the counter
| becomes -1, this executes 25 iterations total:
| 24, 23, ..., 0
        MOVEQ   #24,D1                          | SET LOOP COUNT

LOOP1:
| Copy one 32-bit scanline from the embedded bitmap to
| the destination in screen memory.
|
| Source:
| read 4 bytes at A0
| Destination:
| write 4 bytes at A1
|
| The post-increment on A0 advances to the next row in LAYOUT.
        MOVE.L  (A0)+,(A1)                      | COPY LONGWORD

| Advance destination pointer by one framebuffer row.
|
| Since each row of source data is only one longword wide,
| the destination must jump by the full screen row stride
| to reach the next scanline position.
        ADD     D0,A1                           | ADD ROWBYTES

| Decrement D1 and repeat until it reaches -1.
|
| Total iterations: 25
| Total copied: 25 longwords = 100 bytes
        DBF     D1,LOOP1                        | LOOP

LOOP2:
| Infinite loop.
|
| Once the bitmap has been drawn, the machine spins here
| forever. This effectively freezes execution with the
| image left on screen.
        BRA.B   LOOP2                           | CONTINUE

| ----------------------------------------------------------
|
| LAYOUT
|
| Embedded 1-bit bitmap data: "STOLEN FROM APPLE COMPUTER"
|
| Layout:
| - 25 rows
| - 4 bytes per row
| - 32 pixels wide
|
| So this is a 32 x 25 monochrome image stored uncompressed.
| The routine above copies one longword per scanline.
|
LAYOUT:
  .byte 0x00,0x00,0x00,0x00                     | SCANLINE 0 (BLANK)
  .byte 0x7E,0xE9,0xD2,0x00                     | SCANLINE 1: "macin"
  .byte 0x44,0xA9,0x1A,0x00                     | SCANLINE 2
  .byte 0x74,0xA9,0x96,0x10                     | SCANLINE 3
  .byte 0x14,0xA9,0x12,0x30                     | SCANLINE 4
  .byte 0x74,0xEF,0xD2,0x60                     | SCANLINE 5
  .byte 0x00,0x00,0x00,0x40                     | SCANLINE 6 (GAP)
  .byte 0x77,0x74,0x43,0x58                     | SCANLINE 7: "tosh" + MAC
  .byte 0x45,0x57,0xC7,0xFC                     | SCANLINE 8
  .byte 0x77,0x55,0x4F,0xFE                     | SCANLINE 9
  .byte 0x46,0x54,0x4F,0xF8                     | SCANLINE 10
  .byte 0x45,0x74,0x4F,0xF0                     | SCANLINE 11
  .byte 0x00,0x00,0x0F,0xF0                     | SCANLINE 12 (GAP + MAC)
  .byte 0x77,0x74,0xEF,0xF8                     | SCANLINE 13: "q.d." + MAC
  .byte 0x55,0x54,0x8F,0xFE                     | SCANLINE 14
  .byte 0x77,0x74,0xCF,0xFE                     | SCANLINE 15
  .byte 0x54,0x44,0x87,0xBC                     | SCANLINE 16
  .byte 0x54,0x47,0xE3,0x18                     | SCANLINE 17
  .byte 0x00,0x00,0x00,0x00                     | SCANLINE 18 (BLANK)
  .byte 0x77,0x45,0xD7,0xFE                     | SCANLINE 19: "by b.a."
  .byte 0x45,0x6D,0x55,0x4A                     | SCANLINE 20
  .byte 0x45,0x55,0xD5,0x6E                     | SCANLINE 21
  .byte 0x45,0x45,0x15,0x4C                     | SCANLINE 22
  .byte 0x77,0x45,0x1D,0x7A                     | SCANLINE 23
  .byte 0x00,0x00,0x00,0x00                     | SCANLINE 24 (BLANK)

| -----------------------------------------------------
|
| GET SOME BYTES AND QUIT
|
GETDONE:
        MOVE.L  A3,-(SP)                        | PUSH DATAPTR
        MOVE    D6,-(SP)                        | PUSH BYTECOUNT
        JSR     GetPicData(PC)                  | GET DATA FROM THEPIC
        BRA     KILL1_EXIT                      | GO TO COMMON SCALING

| ------------------------------------------------------
|
| LOCAL PROCEDURE TO GET AN UNSIGNED BYTE INTO D0 FROM PICTURE
|
| Called by: PicItem, GET2_CONT_11, TEXTOP, PICITEM_DHOK, TEXTOP2 (and 1 more)
GETUBYTE:
        CLR.B   -(SP)                           | ALLOCATE TEMP
        MOVE.L  SP,-(SP)                        | PUSH ADDR OF TEMP
        MOVE    #1,-(SP)                        | PUSH BYTECOUNT
        JSR     GetPicData(PC)                  | GET DATA FROM THEPIC
        CLR     D0                              | GET READY FOR BYTE
        MOVE.B  (SP)+,D0                        | POP RESULT INTO LO BYTE
        RTS                                     | RETURN TO CALLER


| ------------------------------------------------------
|
| LOCAL PROCEDURE TO GET A SIGNED BYTE INTO D0 FROM PICTURE
|
GETSBYTE:
        CLR.B   -(SP)                           | ALLOCATE TEMP
        MOVE.L  SP,-(SP)                        | PUSH ADDR OF TEMP
        MOVE    #1,-(SP)                        | PUSH BYTECOUNT
        JSR     GetPicData(PC)                  | GET DATA FROM THEPIC
        MOVE.B  (SP)+,D0                        | POP RESULT
        EXT     D0                              | SIGN EXTEND TO WORD
        RTS                                     | RETURN TO CALLER


| ------------------------------------------------------
|
| LOCAL PROCEDURE TO GET A WORD FROM PICTURE INTO D0
|
| Called by: ARCOP, ARCOP_CONT_2, COMMENTOP, LONGCOM, GETHNDL
GETWORD:
        CLR.W   -(SP)                           | ALLOCATE TEMP
        MOVE.L  SP,-(SP)                        | PUSH ADDR OF TEMP
        MOVE    #2,-(SP)                        | PUSH BYTECOUNT
        JSR     GetPicData(PC)                  | GET DATA FROM THEPIC
        MOVE    (SP)+,D0                        | RETURN ANSWER IN D0
        RTS                                     | RETURN TO CALLER

| GETWORD_NO -- gET PNSIZE.
| ----------------------------------------------------------
|
| GETWORD_NO
|
GETWORD_NO:

| ----------------------------------------------------------
|
| LOCAL PROCEDURE TO GET A LONG FROM PICTURE INTO D0
|
GETLONG:
        CLR.L   -(SP)                           | ALLOCATE TEMP
        MOVE.L  SP,-(SP)                        | PUSH ADDR OF TEMP
        MOVE    #4,-(SP)                        | PUSH BYTECOUNT
        JSR     GetPicData(PC)                  | GET DATA FROM THEPIC
        MOVE.L  (SP)+,D0                        | RETURN ANSWER IN D0
        RTS                                     | RETURN TO CALLER

| GETRECT -- gET AND PUSH DSTRECT.
| ----------------------------------------------------------
|
| GETRECT
|
GETRECT:

| ----------------------------------------------------------
|
| LOCAL PROCEDURE TO SET UP AND PUSH DSTRECT AS FOLLOWS:
| IF NOT SAMEFLAG, THEN GET NEXT 8 BYTES INTO THERECT.
| THEN MAP THERECT INTO DSTRECT, AND PUSH ADDR OF DSTRECT.
| CLOBBERS A0,D0
|
        TST.B   -0x28(A6)                       | SAME RECT ?

| ----------------------------------------------------------
|
        BNE.B   SAME1                           | YES, CONTINUE
        MOVE.L  0x8(A6),A2                      | POINT TO PLAYSTATE RECORD
        PEA.L   (A2)                            | PUSH ADDR OF THERECT
        MOVE    #8,-(SP)                        | PUSH BYTECOUNT
        JSR     GetPicData(PC)                  | GET DATA FROM THEPIC
SAME1:
        MOVE.L  0x8(A6),A2                      | POINT TO PLAYSTATE RECORD
        MOVE.L  (A2),-0x10(A6)                  | COPY THERECT INTO DSTRECT
        MOVE.L  0x4(A2),-0xC(A6)                | COPY THERECT INTO DSTRECT
        PEA.L   -0x10(A6)                       | PUSH LOCAL POINT
        PEA.L   0x14(A2)                        | PUSH SOURCE RECT
        PEA.L   0x1C(A2)                        | PUSH DEST RECT
        JSR     MapRect(PC)                     | MAP DSTRECT
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        PEA.L   -0x10(A6)                       | PUSH ADDR OF MAPPED DSTRECT
        JMP     (A0)                            | RETURN

| SAME1_CONT -- cOPY RGN INTO HANDLE1.
| ----------------------------------------------------------
|
| SAME1_CONT
|
SAME1_CONT:

| --------------------------------------------------------
|
| LOCAL ROUTINE TO ALLOCATE, AND COPY HANDLE1
|
| CLOBBERS D0-D2,A0-A1,D4,D5
|
| TRICKY ENTRY AT GETHND2 WITH COUNT IN D0, D4 = 0
|
GETHNDL:
        MOVEQ   #2,D4                           | INIT BYTE OFFSET FOR LATER
        BSR.B   GETWORD                         | GET BYTECOUNT
| GETHND2 -- gET DATA INTO HANDLE1.
GETHND2:
        EXT.L   D0                              | MAKE COUNT LONG
        MOVE.L  D0,D5                           | PUT BYTECOUNT INTO D5
        _NewHandle                              | ALLOCATE HANDLE
        BNE     KILL1_ERR                       | ABORT IF MEMFULL
        MOVE.L  A0,-0x4(A6)                     | SAVE IN HANDLE1
        _HLock                                  | LOCK HANDLE1
        MOVE.L  -0x4(A6),A0                     | GET HANDLE1
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        MOVE    D5,(A0)                         | INSTALL SIZE WORD
        SUB     D4,D5                           | ADJUST COUNT
        PEA.L   0x0(A0,D4.W)                    | PUSH DATAPTR
        MOVE    D5,-(SP)                        | PUSH BYTECOUNT
        JSR     GetPicData(PC)                  | GET DATA FROM THEPIC
        MOVE.L  -0x4(A6),A0                     | GET HANDLE 1
        _HLock                                  | LOCK HANDLE 1
        RTS                                     | AND RETURN

| _HLock ;LOCK IT

| -----------------------------------------------------------------
|
| CALL BOTTLENECK PROC, DISPOSE OF ONE OR TWO HANDLES, AND QUIT
|
CALL0:
        JSR     (A0)                            | CALL PROC PTR
        BRA.B   KILL1_EXIT                      | AND QUIT

| ----------------------------------------------------------
|
| CALL1
|
CALL1:
        JSR     (A0)                            | CALL PROC PTR
        BRA.B   KILL1                           | KILL HANDLE1 AND QUIT

|
| KILL ONE OR TWO HANDLE TEMPS
|
KILL2:
        MOVE.L  -0x8(A6),A0                     | GET HANDLE2
        _DisposeHandle                          | DISCARD HANDLE2

| _DisposHandle ;DISCARD IT
KILL1:
        MOVE.L  -0x4(A6),A0                     | GET HANDLE1
        _DisposeHandle                          | DISCARD HANDLE1

| _DisposHandle ;DISCARD IT
|
| KILL ONE OR TWO HANDLE TEMPS
|
        BRA.B   KILL1_EXIT                      | GO TO COMMON SCALING

| ----------------------------------------------------------
|
| KILL1_ERR
|
KILL1_ERR:
        MOVE.L  -0x138(A6),SP                   | RESTORE STACK
        CLR.B   0xC(A6)                         | RETURN FALSE
| Called by: PicItem, GET2_CONT_9, GET2_CONT_10, GET2_CONT_11, GET2_CONT_15 (and 3 more)
KILL1_EXIT:
        MOVEM.L (SP)+,D3-D7/A2-A4               | DONE: RESTORE REGISTERS
        UNLK    A6                              | RESTORE STACK FRAME
        MOVE.L  (SP)+,(SP)                      | STRIP PARAMETERS BUT KEEP RETURN ADDRESS
        RTS                                     | RETURN TO CALLER

| .FUNC GetPicData,2
| .REF StdGetPic
| ------------------------------------------------------------------
|
| FUNCTION GetPicData(dataPtr: QDPtr; byteCount: INTEGER);
|
| Called by: TEXTOP2, ARCOP_CONT_2, PICITEM_MORE1, PICITEM_NOPACK, GETDONE (and 6 more)
GetPicData:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE.L  GRAFPROCS(A0),D0                | IS GRAFPROCS NIL ?
        MOVE.L  (0xFB8).w,A0                    | _StdGetPic (getPicProc)
        BEQ.B   GETPICDATA_EMPTY                | BRANCH IF ZERO
        MOVE.L  D0,A0                           | NOTSTD
        MOVE.L  GETPICPROC(A0),A0               | NO, GET GET PROC PTR
GETPICDATA_EMPTY:
        JMP     (A0)                            | AND CALL IT

| .PROC PutPicData,2
| .REF StdPutPic
| ------------------------------------------------------
|
| PROCEDURE PutPicData(dataPtr: QDPtr; byteCount:INTEGER);
| ADD SOME BYTES TO THEPIC.
|
| Called by: NOPACK, TEXT2, MORE1, MORE2, STDCOMMENT_OK (and 6 more)
PutPicData:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE.L  GRAFPROCS(A0),D0                | IS GRAFPROCS NIL ?
        MOVE.L  (0xFC0).w,A0                    | _StdPutPic (putPicProc)
        BEQ.B   PUTPICDATA_EMPTY                | BRANCH IF ZERO
        MOVE.L  D0,A0                           | NOTSTD
        MOVE.L  PUTPICPROC(A0),A0               | NO, GET GET PROC PTR
PUTPICDATA_EMPTY:
        JMP     (A0)                            | AND CALL IT

| DPutPicByte -- aDD TO THEPIC.
| ----------------------------------------------------------
|
| D Put Pic Byte
|
| Called by: FONTOK, COUNTOK, FACEOK, StdRRect, StdPoly (and 14 more)
DPutPicByte:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.B  D0,-(SP)                        | PUSH DATA BYTE
        MOVE.L  A0,-(SP)                        | PUSH RETURN ADDR

| .PROC DPutPicByte,1
| .DEF PutPicByte
| .REF PutPicData
| ------------------------------------------------------
|
| PROCEDURE PutPicByte(data: Byte);
|
| Called by: DHDV, PUTOP, NOPACK, MORE1, ClosePicture
PutPicByte:
| PutPicByte
        PEA.L   0x4(SP)                         | PUSH ADDR OF DATA
        MOVE    #1,-(SP)                        | PUSH BYTECOUNT = 1
        JSR     PutPicData(PC)                  | CALL PutPicData
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        TST.B   (SP)+                           | STRIP PARAM
        JMP     (A0)                            | AND RETURN

| PutPicWord -- pUT KIND.
| ----------------------------------------------------------
|
| Put Pic Word
|
| Called by: StdArc, STDCOMMENT_OK, COUNTOK, FACEOK, STDTEXT_MODEOK (and 4 more)
PutPicWord:
| .PROC PutPicWord,1
| .REF PutPicData
| ------------------------------------------------------
|
| PROCEDURE PutPicWord(data: INTEGER);
|
        PEA.L   0x4(SP)                         | PUSH ADDR OF DATA
        MOVE    #2,-(SP)                        | PUSH BYTECOUNT = 2
        JSR     PutPicData(PC)                  | CALL PutPicData
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        TST     (SP)+                           | STRIP PARAM
        JMP     (A0)                            | AND RETURN

| PutPicLong -- yES, PUT STARTPT = PNLOC.
| ----------------------------------------------------------
|
| Put Pic Long
|
| Called by: PUTOP, STDLINE_STARTOK, StdRRect, FRAME1, CheckPic (and 2 more)
PutPicLong:
| .PROC PutPicLong,1
| .REF PutPicData
| ------------------------------------------------------
|
| PROCEDURE PutPicLong(data: LongInt);
|
        PEA.L   0x4(SP)                         | PUSH ADDR OF DATA
        MOVE    #4,-(SP)                        | PUSH BYTECOUNT = 4
        JSR     PutPicData(PC)                  | CALL PutPicData
        MOVE.L  (SP)+,(SP)                      | STRIP PARAM
        RTS                                     | RETURN TO CALLER

| PutPicPat -- pUT PATTERN DATA.
| ----------------------------------------------------------
|
| Put Pic Pat
|
PutPicPat:
| .PROC PutPicPat,1
| .REF PutPicData
| ------------------------------------------------------
|
| PROCEDURE PutPicPat(pat: Pattern);
|
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE    #8,-(SP)                        | PUSH BYTECOUNT = 8
        MOVE.L  A0,-(SP)                        | PUSH RETURN ADDR
        JMP     PutPicData(PC)                  | SAVE PICTURE DATA

| PutPicRect -- pUT OPCODE AND RECTANGLE.
| ----------------------------------------------------------
|
| Put Pic Rect
|
PutPicRect:
| .PROC PutPicRect,2
| .REF DPutPicByte,PutPicData
| ------------------------------------------------------
|
| PROCEDURE PutPicRect(opCode: Byte; r: Rect);
|
| Add an opcode and rectangle to thePic and update picTheRect state variable.
| If rect is the same as picTheRect, then just add 8 to the Opcode.
|
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF RECT
        MOVE.B  (SP)+,D0                        | POP OPCODE
        MOVE.L  A0,-(SP)                        | PUSH RETURN ADDR
        MOVE.L  (A1),D2                         | GET TOPLEFT
        MOVE.L  0x4(A1),D1                      | GET BOTRIGHT
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE.L  PICSAVE(A0),A0                  | GET PICSAVE HANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE PICSAVE
        CMP.L   PICTHERECT(A0),D2               | IS TOPLEFT THE SAME ?
        BNE.B   NOTSAME                         | NO, CONTINUE
        CMP.L   0x4E(A0),D1                     | IS BOTRIGHT THE SAME ?
        BNE.B   NOTSAME                         | NO, CONTINUE
        ADDQ.W  #0x8,D0                         | ADD HEADER SIZE
        JMP     DPutPicByte(PC)                 | PUT MODIFIED OPCODE AND RETURN

| ----------------------------------------------------------
|
| NOTSAME
|
NOTSAME:
        MOVE.L  D2,PICTHERECT(A0)               | UPDATE PICTHERECT
        MOVE.L  D1,0x4E(A0)                     | SAVE IN GLOBALS
        MOVE.L  A1,-(SP)                        | PUSH ADDR OF RECT FOR BELOW
        MOVE    #8,-(SP)                        | PUSH BYTECOUNT FOR BELOW
        JSR     DPutPicByte(PC)                 | PUT OPCODE (IN D0)
        JSR     PutPicData(PC)                  | PUT 8 BYTES OF RECTANGLE
        RTS                                     | DONE

| .PROC PutPicRgn,1
| .REF PutPicData
| ------------------------------------------------------
|
| PROCEDURE PutPicRgn(rgn: RgnHandle);
| ALSO called to put a polygon.
|
| _HLock ;LOCK IT
PutPicRgn:
        MOVE.L  0x4(SP),A0                      | PUSH RGNHANDLE
        _HLock                                  | LOCK REGION HANDLE
        MOVE.L  0x4(SP),A0                      | GET HANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        MOVE.L  A0,-(SP)                        | PUSH DATAPTR
        MOVE    (A0),-(SP)                      | PUSH BYTECOUNT
        JSR     PutPicData(PC)                  | ADD TO THEPIC
        MOVE.L  0x4(SP),A0                      | GET RGNHANDLE
        _HUnlock                                | UNLOCK IT
        MOVE.L  (SP)+,(SP)                      | STRIP PARAM
        RTS                                     | RETURN TO CALLER

| PutPicVerb -- pUT ADDIONAL PARAMS TO THEPIC.
| ----------------------------------------------------------
|
| Put Pic Verb
|
| Called by: StdLine, StdRect, StdRRect, StdOval, StdArc (and 2 more)
PutPicVerb:
| .PROC PutPicVerb,1
| .REF DPutPicByte,PutPicWord,PutPicLong,PutPicPat
| ------------------------------------------------------
|
| PROCEDURE PutPicVerb(verb: GrafVerb);
|
| check additional picture params associated with
| this verb, and add those that have changed to thePic.
|
| PARAMSIZE .EQU 2
| VERB .EQU PARAMSIZE+8-2 ;BYTE
.set PARAMSIZE, 2                               | TOTAL BYTES OF PARAMS
.set VERB, PARAMSIZE+8-2                        | BYTE

        LINK    A6,#0                           | NO LOCAL VARS
        MOVEM.L D5-D7/A3-A4,-(SP)               | SAVE REGS
        MOVE.L  (A5),A4                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A4),A3                         | GET CURRENT GRAFPORT
        MOVE.L  PICSAVE(A3),A4                  | GET PICSAVE HANDLE
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE
        MOVE.B  0x8(A6),D7                      | GET VERB
        CMPI.B  #0x1,D7                         | CASE JUMP BASSED ON VERB
        BLT.B   FRAME1                          | BRANCH IF FRAME
        BEQ     PAINT1                          | YES CHECK PNMODE, PNPAT
        CMPI.B  #0x3,D7                         | IS VERB INVERT ?
        BEQ     PAINT1_EXIT                     | YES, NOTHING TO CHECK
        BLT.B   ERASE1                          | BRANCH IF ERASE
        MOVE.L  FILLPAT(A3),D5                  | FILL1: GET FILLPAT
        MOVE.L  0x2C(A3),D6                     | GET FILLPAT
        CMP.L   PICFILLPAT(A4),D5               | SAME AS PICFILLPAT ?
        BNE.B   PUTPICVERB_NO                   | NO, PUT CHANGE TO THEPIC
        CMP.L   0x46(A4),D6                     | COMPARE WITH SAVED PATTERN
        BEQ     PAINT1_EXIT                     | IF EQUAL, SKIP
PUTPICVERB_NO:
        MOVE.L  D5,0x42(A4)                     | SAVE NEW PATTERN
        MOVE.L  D6,0x46(A4)                     | SAVE NEW PATTERN
        MOVEQ.L #0xA,D0                         | PUSH FILLPAT OPCODE
        JSR     DPutPicByte(PC)                 | ADD TO THEPIC
        PEA.L   FILLPAT(A3)                     | PUSH FILL PATTERN
        JSR     PutPicPat(PC)                   | PUT PATTERN DATA
        BRA     PAINT1_EXIT                     | AND QUIT

| ----------------------------------------------------------
|
| ERASE1
|
ERASE1:
        MOVE.L  BKPAT(A3),D5                    | GET BKPAT
        MOVE.L  0x24(A3),D6                     | GET BKPAT
        CMP.L   PICBKPAT(A4),D5                 | SAME AS PICBKPAT ?
        BNE.B   NEWBK                           | NO, PUT CHANGE TO THEPIC
        CMP.L   0x14(A4),D6                     | COMPARE WITH SAVED BKPAT
        BEQ     PAINT1_EXIT                     | IF EQUAL, SKIP
NEWBK:
        MOVE.L  D5,PICBKPAT(A4)                 | UPDATE STATE VARIABLE
        MOVE.L  D6,0x14(A4)                     | SAVE NEW BKPAT
        MOVEQ.L #0x2,D0                         | BKPAT OPCODE
        JSR     DPutPicByte(PC)                 | ADD TO THEPIC
        PEA.L   BKPAT(A3)                       | PUSH BACKGROUND PATTERN
        JSR     PutPicPat(PC)                   | PUT PATTERN DATA
        BRA.B   PAINT1_EXIT                     | AND QUIT

| ----------------------------------------------------------
|
| FRAME1
|
FRAME1:
        MOVE.L  PNSIZE(A3),D6                   | GET PNSIZE
        CMP.L   PICPNSIZE(A4),D6                | HAS IT CHANGED ?
        BEQ.B   PAINT1                          | NO, CONTINUE
        MOVEQ.L #0x7,D0                         | SET OPCODE FOR PATERNN
        JSR     DPutPicByte(PC)                 | YES, PUT PNSIZE OPCODE
        MOVE.L  D6,-(SP)                        | PUSH ARGUMENT
        JSR     PutPicLong(PC)                  | PUT NEW PNSIZE
        MOVE.L  PICSAVE(A3),A4                  | GET PICSAVE HANDLE
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE
        MOVE.L  D6,PICPNSIZE(A4)                | AND UPDATE STATE VARIABLE
PAINT1:
        MOVE    PNMODE(A3),D6                   | GET PNMODE
        CMP     PICPNMODE(A4),D6                | HAS IT CHANGED ?
        BEQ.B   PAINT1_NO                       | NO, CONTINUE
        MOVEQ.L #0x8,D0                         | SET OPCODE FOR PNMODE
        JSR     DPutPicByte(PC)                 | YES, PUT PNMODE OPCODE
        MOVE    D6,-(SP)                        | PUSH KIND
        JSR     PutPicWord(PC)                  | PUT NEW PNMODE
        MOVE.L  PICSAVE(A3),A4                  | GET PICSAVE HANDLE
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE
        MOVE    D6,PICPNMODE(A4)                | AND UPDATE STATE VARIABLE
PAINT1_NO:
        MOVE.L  PNPAT(A3),D5                    | MODEOK: GET PNPAT
        MOVE.L  0x3E(A3),D6                     | GET PNPAT
        CMP.L   PICPNPAT(A4),D5                 | SAME AS PICPNPAT ?
        BNE.B   PAINT1_NO_2                     | NO, PUT CHANGE TO THEPIC
        CMP.L   0x3E(A4),D6                     | COMPARE WITH SAVED PNPAT
        BEQ.B   PAINT1_EXIT                     | IF EQUAL, SKIP
PAINT1_NO_2:
        MOVE.L  D5,0x3A(A4)                     | SAVE NEW PNPAT
        MOVE.L  D6,0x3E(A4)                     | SAVE NEW PNPAT
        MOVEQ.L #0x9,D0                         | PNPAT OPCODE
        JSR     DPutPicByte(PC)                 | ADD TO THEPIC
        PEA.L   PNPAT(A3)                       | PUSH PEN PATTERN
        JSR     PutPicPat(PC)                   | PUT PATTERN DATA
PAINT1_EXIT:
        MOVEM.L (SP)+,D5-D7/A3-A4               | DONE: RESTORE REGS
        UNLK    A6                              | RESTORE STACK FRAME
        MOVE.L  (SP)+,A0                        | GET RETURN ADDRESS
        ADDQ.W  #0x2,SP                         | POP PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER

| ----------------------------------------------------------
|
| Check Pic
|
| Called during boot.
CheckPic:
| .PROC CheckPic,0
| .REF EqualRgn,CopyRgn
| .REF DPutPicByte,PutPicLong,PutPicRgn
| ---------------------------------------------------------------
|
| PROCEDURE CheckPic;
|
| PUT GRAFGLOBALS IN A4, THEPORT IN A3, AND CHECK PICSAVE.
| IF PICSAVE IS NIL, RETURN FLAGS LE.
|
| IF PICSAVE NOT NIL, RETURN FLAGS GT, AND
| CHECK FOR CHANGES IN FGCOLOR, BKCOLOR, ORIGIN, AND CLIPRGN.
|
        MOVE.L  D7,-(SP)                        | SAVE REGS
        MOVE.L  (A5),A4                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A4),A3                         | GET CURRENT GRAFPORT
        TST.L   PICSAVE(A3)                     | ARE WE SAVING FOR A PICTURE ?
        BEQ     ORIGNOK_EXIT_2                  | NO, QUIT
        CMPI    #-0x1,PNVIS(A3)                 | IS PEN HIDDEN MORE THAN ONE ?
        BLT     ORIGNOK_EXIT_2                  | YES, DON'T ADD TO THEPIC
        MOVE.L  PICSAVE(A3),A4                  | YES, GET PICSAVE HANDLE
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE

|
| CHECK FOR CHANGES IN FOREGROUND COLOR
|
        MOVE.L  FGCOLOR(A3),D7                  | GET FORGROUND COLOR
        CMP.L   PICFGCOLOR(A4),D7               | HAS IT CHANGED ?
        BEQ.B   CHECKPIC_NO                     | NO, CONTINUE
        MOVEQ.L #0xE,D0                         | SET OPCODE FOR FGCOLOR
        JSR     DPutPicByte(PC)                 | PUT FGCOLOR OPCODE
        MOVE.L  D7,-(SP)                        | PUSH COLOR
        JSR     PutPicLong(PC)                  | PUT FGCOLOR
        MOVE.L  PICSAVE(A3),A4                  | GET PICSAVE HANDLE
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE
        MOVE.L  D7,PICFGCOLOR(A4)               | UPDATE CURRENT STATE

| FGCOLOK
|
| CHECK FOR CHANGES IN BACKGROUND COLOR
|
CHECKPIC_NO:
        MOVE.L  BKCOLOR(A3),D7                  | GET BACKGROUND COLOR
        CMP.L   PICBKCOLOR(A4),D7               | HAS IT CHANGED ?
        BEQ.B   CHECKPIC_NO_2                   | NO, CONTINUE
        MOVEQ.L #0xF,D0                         | SET OPCODE FOR BKCOLOR
        JSR     DPutPicByte(PC)                 | PUT BKCOLOR OPCODE
        MOVE.L  D7,-(SP)                        | PUSH COLOR
        JSR     PutPicLong(PC)                  | PUT BKCOLOR PARAM
        MOVE.L  PICSAVE(A3),A4                  | GET PICSAVE HANDLE
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE
        MOVE.L  D7,PICBKCOLOR(A4)               | UPDATE CURRENT STATE
CHECKPIC_NO_2:
        MOVE.L  PORTRECT(A3),D0                 | GET PORTRECT.TOPLEFT

| BKCOLOK
|
| CHECK FOR ORIGIN CHANGES
|
        CMP.L   PICORIGIN(A4),D0                | SAME AS PIC ORIGIN ?
        BEQ.B   ORIGNOK                         | YES, CONTINUE
        MOVE    0x12(A3),D7                     | GET PORTRECT LEFT
        SUB     0x58(A4),D7                     | CALC DH
        ADD     D7,0x58(A4)                     | UPDATE STATE VARIABLE
        SWAP    D7                              | PUT DH IN HI WORD
        MOVE    PORTRECT(A3),D7                 | GET PORTRECT TOP
        SUB     0x56(A4),D7                     | CALC DV
        ADD     D7,0x56(A4)                     | UPDATE STATE VARIABLE
        MOVEQ.L #0xC,D0                         | SET OPCODE FOR TXCOLOR
        JSR     DPutPicByte(PC)                 | PUT ORIGIN OPCODE TO THEPIC
        MOVE.L  D7,-(SP)                        | PUSH COLOR
        JSR     PutPicLong(PC)                  | PUT DH,DV TO THEPIC
        MOVE.L  PICSAVE(A3),A4                  | GET PICSAVE HANDLE
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE

|
| CHECK FOR CLIPRGN CHANGES
|
ORIGNOK:
        CLR.B   -(SP)                           | MAKE ROOM FOR FCN VALUE
        MOVE.L  CLIPRGN(A3),-(SP)               | PUSH CLIPRGN
        MOVE.L  PICCLIPRGN(A4),-(SP)            | PUSH STATE VARIABLE
        JSR     EqualRgn(PC)                    | ARE THEY THE SAME ?
        TST.B   (SP)+                           | TEST RESULT
        BNE.B   CLIPOK                          | QUIT IF SAME
        MOVE.L  CLIPRGN(A3),-(SP)               | SET UP FOR COPYRGN BELOW
        MOVE.L  PICCLIPRGN(A4),-(SP)            | PUSH CLIP REGION
        MOVEQ.L #0x1,D0                         | SET CLIP OPCODE
        JSR     DPutPicByte(PC)                 | PUT CLIPRGN PARAM OPCODE
        MOVE.L  CLIPRGN(A3),-(SP)               | PUSH CLIPRGN HANDLE
        JSR     PutPicRgn(PC)                   | PUT CLIPRGN TO THEPIC
        JSR     CopyRgn(PC)                     | COPY CLIPRGN INTO PICCLIPRGN
CLIPOK:
        MOVE.L  (A5),A4                         | POINT TO QUICKDRAW GLOBALS
        MOVEQ   #1,D0                           | CLEAR ZERO FLAG
ORIGNOK_EXIT_2:
        MOVEM.L (SP)+,D7                        | DONE: MOVEM FOR CC, RESTORE REGS
        RTS                                     | RETURN TO CALLER

| .PROC ScalePt
| -------------------------------------------------------------
|
| PROCEDURE ScalePt(VAR pt: Point; fromRect,toRect: Rect);
|
| Scale a width and height from one coordinate system to another.
| If fromRect and toRect are the same size, then no change.
| If the input > 0, then enforce 1 pixel minimum on the output.
|
| pt.h := (pt.h * fromWidth) / toWidth
| pt.v := (pt.v * fromHeight) / toHeight
|
| restores ALL registers.
|
| A6 OFFSETS OF PARAMS AFTER LINK:
|
| PARAMSIZE .EQU 12 ;TOTAL BYTES OF PARAMS
| PT .EQU PARAMSIZE+8-4 ;LONG, ADDR OF POINT
| FROMRECT .EQU PT-4 ;LONG, ADDR OF RECT
| TORECT .EQU FROMRECT-4 ;LONG, ADDR OF RECT
ScalePt:
| RTS ;AND RETURN
.set PARAMSIZE, 12                              | TOTAL BYTES OF PARAMS
.set PT, PARAMSIZE+8-4                          | LONG, ADDR OF POINT
.set FROMRECT, PT-4                             | LONG, ADDR OF RECT
.set TORECT, FROMRECT-4                         | LONG, ADDR OF RECT

        LINK    A6,#0                           | NO LOCALS
        MOVEM.L D0-D6/A0-A2,-(SP)               | SAVE REGS
        MOVE.L  0x10(A6),A0                     | POINT TO VAR PT
        MOVE.L  0xC(A6),A1                      | POINT TO FROMRECT
        MOVE.L  0x8(A6),A2                      | POINT TO TORECT
        BSR.B   SCALEPT_CONT                    | SCALE THE HEIGHT
        ADDQ.W  #0x2,A0                         | OFFSET TO PT.H
        ADDQ.W  #0x2,A1                         | OFFSET TO FROMRECT.H
        ADDQ.W  #0x2,A2                         | OFFSET TO TORECT.H
        BSR.B   SCALEPT_CONT                    | SCALE THE WIDTH
        MOVEM.L (SP)+,D0-D6/A0-A2               | DONE: RESTORE REGS
        UNLK    A6                              | RESTORE STACK FRAME
        MOVE.L  (SP)+,A0                        | GET RETURN ADDRESS
        ADDA    #0xC,SP                         | POP PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER

| SCALEPT_CONT -- sCALE THE HEIGHT.
| ----------------------------------------------------------
|
| SCALEPT_CONT
|
SCALEPT_CONT:

| -------------------------------------------------------
|
| LOCAL ROUTINE TO SCALE A SINGLE WIDTH OR HEIGHT:
| IF INPUT <= 0, THEN OUTPUT WILL BE 0.
| IF INPUT > 0, THEN OUTPUT WILL BE AT LEAST 1.
|
SCALE1:
        MOVE    BOTTOM(A1),D3                   | GET FROMRECT BOTTOM
        SUB     (A1),D3                         | CALC FROMHEIGHT
        MOVE    BOTTOM(A2),D2                   | GET TORECT BOTTOM
        SUB     (A2),D2                         | CALC TORECT HEIGHT
        CMP     D2,D3                           | ARE BOTH HEIGHTS THE SAME ?
        BEQ.B   SCDONE                          | YES, SKIP
        MOVE    D3,D1                           | COPY DENOM = FROMHEIGHT
        LSR     #1,D1                           | CALC DENOM/2 (DENOM IS POS)
        EXT.L   D1                              | MAKE IT LONG
        MOVE    (A0),D0                         | GET SIZE COORD
        BGT.B   POS                             | CONTINUE IF POSITIVE
        CLR     (A0)                            | ELSE SET IT TO ZERO
        RTS                                     | AND QUIT

| ----------------------------------------------------------
|
| POS
|
POS:
        MULU    D2,D0                           | MULT BY TORECT HEIGHT
        ADD.L   D1,D0                           | ADD FROMHEIGHT/2 FOR ROUNDING
        DIVU    D3,D0                           | DIV BY FROMHEIGHT
        BNE.B   MINSIZE_EMPTY                   | IS RESULT ZERO ?
MINSIZE:
        MOVEQ   #1,D0                           | ENFORCE 1 PIXEL MIN SIZE
MINSIZE_EMPTY:
        MOVE    D0,(A0)                         | SIZEOK: UPDATE RESULT
SCDONE:
        RTS                                     | RETURN TO CALLER

| .PROC MapPt
| -------------------------------------------------------------
|
| PROCEDURE MapPt(VAR pt: Point; fromRect,toRect: Rect);
|
| Map a point from one coordinate system to another.
|
| pt.h := ((pt.h-fromLeft) * toWidth) / fromWidth + toLeft
| pt.v := ((pt.v-fromTop) * toHeight) / fromHeight + toTop
|
| restores ALL registers.
|
| A6 OFFSETS OF PARAMS AFTER LINK:
|
| PARAMSIZE .EQU 12 ;TOTAL BYTES OF PARAMS
| PT .EQU PARAMSIZE+8-4 ;LONG, ADDR OF POINT
| FROMRECT .EQU PT-4 ;LONG, ADDR OF RECT
| TORECT .EQU FROMRECT-4 ;LONG, ADDR OF RECT
| Called by: MapRect, MAPPOLY_NEXTPT, MAPRGN_LOOP, LNFROM, LNOK (and 1 more)
MapPt:
.set PARAMSIZE, 12                              | TOTAL BYTES OF PARAMS
.set PT, PARAMSIZE+8-4                          | LONG, ADDR OF POINT
.set FROMRECT, PT-4                             | LONG, ADDR OF RECT
.set TORECT, FROMRECT-4                         | LONG, ADDR OF RECT

        LINK    A6,#0                           | NO LOCALS
        MOVEM.L D0-D6/A0-A2,-(SP)               | SAVE REGS
        MOVE.L  0x10(A6),A0                     | POINT TO VAR PT
        MOVE.L  0xC(A6),A1                      | POINT TO FROMRECT
        MOVE.L  0x8(A6),A2                      | POINT TO TORECT
        BSR.B   MAP1                            | MAP THE VERTICAL COORD
        ADDQ.W  #0x2,A0                         | OFFSET TO PT.H
        ADDQ.W  #0x2,A1                         | OFFSET TO FROMRECT.H
        ADDQ.W  #0x2,A2                         | OFFSET TO TORECT.H
        BSR.B   MAP1                            | MAP THE HORIZ COORD
        MOVEM.L (SP)+,D0-D6/A0-A2               | DONE: RESTORE REGS
        UNLK    A6                              | RESTORE STACK FRAME
        MOVE.L  (SP)+,A0                        | GET RETURN ADDRESS
        ADDA    #0xC,SP                         | POP PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER

| MAP1 -- mAP THE VERTICAL COORD.
| ----------------------------------------------------------
|
| MAP1
|
MAP1:
        MOVE    (A1),D2                         | GET DATA

| -----------------------------------------------
|
| LOCAL ROUTINE TO MAP A SINGLE COORDINATE:
|
        MOVE    BOTTOM(A1),D3                   | GET FROMRECT BOTTOM
        SUB     D2,D3                           | CALC FROMHEIGHT
        MOVE    (A2),D4                         | GET TORECT TOP
        MOVE    BOTTOM(A2),D5                   | GET TORECT BOTTOM
        SUB     D4,D5                           | CALC TORECT HEIGHT
        MOVE    (A0),D0                         | GET COORD
        SUB     D2,D0                           | SUBTRACT FROMRECT TOP
        CMP     D3,D5                           | ARE BOTH HEIGHTS SAME ?
        BEQ.B   NOSCALE                         | YES, SKIP THE SCALING
        MOVE    D3,D1                           | DENOM = FROMHEIGHT
        LSR     #1,D1                           | CALC DENOM/2 (DENOM ALWAYS POS)
        EXT.L   D1                              | MAKE DENOM/2 LONG
        MOVE    D0,D2                           | IS COORD NEGATIVE ?
        BPL.B   NOTNEG                          | NO, CONTINUE
        NEG     D0                              | YES, MAKE IT POSITIVE FOR MULDIV
NOTNEG:
        MULU    D5,D0                           | MULT COORD BY TORECT HEIGHT
        ADD.L   D1,D0                           | ADD FROMHEIGHT/2 FOR ROUNDING
        DIVU    D3,D0                           | DIV BY FROMHEIGHT
        TST     D2                              | WAS OLD COORD NEG ?
        BPL.B   NOSCALE                         | NO, CONTINUE
        NEG     D0                              | YES, RESTORE IT TO NEGATIVE
NOSCALE:
        ADD     D4,D0                           | ADD TORECT TOP
        MOVE    D0,(A0)                         | UPDATE RESULT
        RTS                                     | RETURN TO CALLER

| .PROC MapRect,3
| .REF MapPt
| -------------------------------------------------------------
|
| PROCEDURE MapRect(VAR dstRect: Rect; fromRect,toRect: Rect);
|
| Map both points of a rectangle from one coordinate system to another.
| restores ALL registers.
|
| Called by: NOSLOP, DOWN2, MAPPOLY_NOTSAME, MAPRGN_NO, ARCOP_CONT_2 (and 1 more)
MapRect:
| RTS
        MOVE.L  0xC(SP),-(SP)                   | PUSH DSTRECT
        MOVE.L  0xC(SP),-(SP)                   | PUSH FROMRECT
        MOVE.L  0xC(SP),-(SP)                   | PUSH TORECT
        JSR     MapPt(PC)                       | MAP TOPLEFT POINT
        ADDQ.L  #0x4,0xC(SP)                    | OFFSET RECT TO BOTRIGHT
        JMP     MapPt(PC)                       | MAP BOTRIGHT AND RETURN


