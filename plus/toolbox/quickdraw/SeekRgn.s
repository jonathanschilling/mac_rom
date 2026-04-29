| ------------------------------------------------------------------
|
| --> SEEKRGN.TEXT
|
| Routines to play back a region into a scanline buffer.
|
|

| .PROC INITRGN,0
| ------------------------------------------------------
|
| INPUTS: A0: RGNPTR
| A1: STATE RECORD
| D0: MINH
| D1: MAXH
| D2: BUFLEFT
|
| OUTPUTS: ALL FIELDS OF STATE RECORD,
| SCANBUF ALLOCATED ON STACK
|
| CLOBBERS: D0,D1,A0
|
| Called during boot.
InitRgn:
        MOVE    D0,MINH(A1)                     | INSTALL MINH
        MOVE    D1,MAXH(A1)                     | INSTALL MAXH
        MOVE    D2,LEFTH(A1)                    | INSTALL LEFTH
        MOVE.L  A0,(A1)                         | SAVE REGION PTR
        MOVE    #-0x7FFF,0xE(A1)                | THISV := -32767
        MOVE    0x2(A0),0x10(A1)                | NEXTV := RGNBBOX.TOP
        LEA.L   RGNDATA(A0),A0                  | POINT TO FIRST DATA
        MOVE.L  A0,DATAPTR(A1)                  | INIT DATAPTR
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        SUB     D2,D1                           | CALC BUFFER WIDTH IN DOTS
        LSR     #5,D1                           | DIV BY 32 FOR #LONGS-1
        MOVE    D1,SCANSIZE(A1)                 | SAVE SCANSIZE FOR LATER
INITRGN_CLRLOOP:
        CLR.L   -(SP)                           | CLRLOOP: ALLOCATE AND CLEAR BUFFER
        DBF     D1,INITRGN_CLRLOOP              | LOOP TILL DONE
        MOVE.L  SP,SCANBUF(A1)                  | REMEMBER BUFFER START
        JMP     (A0)                            | RETURN

| ----------------------------------------------------
|
| RETURN QUICKLY IF SCANBUF IS ALREADY CURRENT.

| .PROC SEEKRGN,0
| .REF MaskTab
| ------------------------------------------------------------------
|
| SeekRgn(rgnState,vert);
|
| ROUTINE TO PLAY BACK A REGION FORWARD OR BACKWARD UNTIL ITS SCAN
| BUFFER CONTAINS THE BITMAP FOR THE GIVEN VERTICAL COORDINATE.
|
| INPUTS: A1 POINTS TO A REGION STATE RECORD
| DO CONTAINS THE DESIRED VERTICAL COORD
|
| OUTPUTS: UPDATES THISV, NEXTV, DATAPTR, AND SCANBUF^ OF STATE RECORD
| D1-->1 IF CHANGE, 0 IF NO CHANGE. (Z-FLAG SET IF NO CHANGE)
|
| CLOBBERS: A0,D1.
|
| Called during boot (1,767 times in 30s trace).
SeekRgn:
        CMP     NEXTV(A1),D0                    | IS DESIRED VERT >= NEXTV ?
        BGE.B   DOWN                            | YES, BUMP DOWNWARD
        CMP     THISV(A1),D0                    | IS DESIRED VERT < CURRENT VERT ?
        BLT.B   UP                              | YES, BUMP UPWARD
        CLR     D1                              | ELSE REPORT NO CHANGES
        RTS                                     | AND RETURN

| -----------------------------------------------------
|
| TO MOVE UPWARDS, JUST RESET TO START AND MOVE DOWN.
|
UP:
        MOVE.L  SCANBUF(A1),A0                  | POINT TO SCANBUF
        MOVE    SCANSIZE(A1),D1                 | GET BUFFER SIZE
SEEKRGN_CLRLP:
        CLR.L   (A0)+                           | CLRLP: CLEAR A LONG
        DBF     D1,SEEKRGN_CLRLP                | LOOP ENTIRE SCANBUF
        MOVE.L  (A1),A0                         | GET REGION PTR
        MOVE    0x2(A0),0x10(A1)                | NEXTV := RGNBBOX.TOP
        MOVE    #-0x7FFF,0xE(A1)                | THISV := -32767
        LEA.L   RGNDATA(A0),A0                  | POINT TO START OF REGION DATA
        MOVE.L  A0,DATAPTR(A1)                  | RESET DATAPTR
        CMP     NEXTV(A1),D0                    | IS DESIRED VERT >= NEXTV ?
        BLT     SEEKRGN_DONE                    | NO, QUIT

| ------------------------------------------------------
|
| WHILE DESIRED VERT >= NEXTV DO BUMP DOWN.
|
| Called during boot.
DOWN:
        MOVEM.L D0-D6/A2-A3,-(SP)               | SAVE REGS
        MOVE    D0,D2                           | SAVE VERT
        MOVE.L  DATAPTR(A1),A2                  | POINT TO VERT COORD
SEEKRGN_DOWN1:
        MOVE    (A2)+,THISV(A1)                 | DOWN1: UPDATE CURRENT VERT

| -------------------------------------------------
|
| GET LEFT AND RIGHT HORIZ COORDS
| AND TRIM AGAINST MINH AND MAXH
|
| Called during boot.
SEEKRGN_NEXTHOR:
        MOVE    (A2)+,D3                        | NEXTHOR: GET LEFT COORD
        CMPI    #0x7FFF,D3                      | IS IT END-OF-SCANLINE ?
        BEQ.B   DONE1                           | YES, QUIT
        MOVE    (A2)+,D4                        | GET RIGHT COORD
        CMP     MINH(A1),D4                     | IS RIGHT <= MINH ?
        BLE.B   SEEKRGN_NEXTHOR                 | YES, IGNORE ON LEFT
        CMP     MAXH(A1),D3                     | IS LEFT >= MAXH ?
        BGE.B   SEEKRGN_NEXTHOR                 | YES, IGNORE ON RIGHT
        CMP     MINH(A1),D3                     | IS LEFT < MINH ?
        BGE.B   LOK                             | NO, CONTINUE
        MOVE    MINH(A1),D3                     | YES, TRIM LEFT
LOK:
        CMP     MAXH(A1),D4                     | IS RIGHT > MAXH ?
        BLE.B   ROK                             | NO, CONTINUE
        MOVE    MAXH(A1),D4                     | YES, TRIM RIGHT
ROK:
        SUB     LEFTH(A1),D3                    | MAKE COORDS REL TO BUFFER
        SUB     LEFTH(A1),D4                    | MAKE RIGHT REL TO BUFFER

| ------------------------------------------
|
| GET LEFTMASK AND RIGHTMASK
|
        LEA.L   DT_mMaskTab(PC),A0              | POINT TO MASK TABLE
        MOVEQ.L #0xF,D0                         | GET MASK FOR LO 4 BITS
        MOVE    D3,D5                           | COPY LEFT COORD
        AND     D0,D5                           | CALC LEFT MOD 16
        ADD     D5,D5                           | DOUBLE FOR INDEX
        MOVE    0x0(A0,D5.W),D5                 | GET LEFT MASK FROM TABLE
        NOT     D5                              | INVERT FOR LEFTMASK
        MOVE    D4,D6                           | COPY RIGHT COORD
        AND     D0,D6                           | CALC RIGHT MOD 16
        ADD     D6,D6                           | DOUBLE FOR INDEX
        MOVE    0x0(A0,D6.W),D6                 | GET RIGHT MASK FROM TABLE

| ------------------------------------------
|
| CALC LEFTWORD, BUFPTR, WORDCOUNT
|
        LSR     #4,D3                           | CONVERT DOTS TO WORDS
        MOVE.L  SCANBUF(A1),A3                  | COPY BUFSTART
        ADD     D3,A3                           | ADD LEFTWORD OFFSET
        ADD     D3,A3                           | INIT BUFPTR TO LEFTWORD
        LSR     #4,D4                           | CALC RIGHT DIV 16
        SUB     D3,D4                           | WORDCOUNT:=RIGHTWORD-LEFTWORD
        BGT.B   NOTIN1                          | BR IF NOT ALL IN ONE

| ------------------------------------------
|
| LEFT AND RIGHT ARE ALL IN ONE WORD
|
        AND     D5,D6                           | COMBINE LEFT AND RIGHT MASKS
        EOR     D6,(A3)                         | XOR COMBINATION INTO BUFFER
        BRA.B   SEEKRGN_NEXTHOR                 | GO FOR MORE DH'S THIS SCAN

| ------------------------------------------
|
| NOT ALL IN ONE WORD. DO LEFT, MIDDLE IF ANY, THEN RIGHT
|
| Called during boot.
NOTIN1:
        EOR     D5,(A3)+                        | XOR LEFTMASK INTO BUFFER
        BRA.B   INVLONG_CONT                    | SEE IF ANY FULL WORDS

| ----------------------------------------------------------
|
| INVLONG
|
| Called during boot.
INVLONG:
        NOT.L   (A3)+                           | INVERT 2 WHOLE WORDS
INVLONG_CONT:
        SUBQ.W  #0x2,D4                         | ADJUST WORDCOUNT
        BGT.B   INVLONG                         | YES, AT LEAST 2
        BLT.B   ENDWORD                         | NO, FINISH UP LAST WITH MASK
        NOT     (A3)+                           | YES, DO LAST FULL WORD
ENDWORD:
        EOR     D6,(A3)                         | XOR RIGHTMASK INTO BUFFER
        BRA.B   SEEKRGN_NEXTHOR                 | GO FOR MORE DH'S THIS SCAN

| ----------------------------------------------------------
|
| DONE1
|
| Called during boot.
DONE1:
        MOVE.L  A2,DATAPTR(A1)                  | UPDATE DATAPTR
        MOVE    (A2),NEXTV(A1)                  | UPDATE NEXT VERT
        CMP     NEXTV(A1),D2                    | IS DESIRED VERT >= NEXTV ?
        BGE     SEEKRGN_DOWN1                   | YES, BUMP DOWN SOME MORE
        MOVEM.L (SP)+,D0-D6/A2-A3               | RESTORE REGS
SEEKRGN_DONE:
        MOVEQ   #1,D1                           | DONE: REPORT SCANLINE CHANGED
        RTS                                     | AND RETURN


