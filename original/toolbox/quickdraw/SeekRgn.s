| ------------------------------------------------------------------
|
| --> SEEKRGN.TEXT
|
| Routines to play back a region into a scanline buffer.

| ------------------------------------------------------------------
| --> SEEKRGN.TEXT
| Routines to play back a region into a scanline buffer.
| .PROC INITRGN,0
| ------------------------------------------------------
| INPUTS: A0: RGNPTR
| A1: STATE RECORD
| D0: MINH
| D1: MAXH
| D2: BUFLEFT
| OUTPUTS: ALL FIELDS OF STATE RECORD,
| SCANBUF ALLOCATED ON STACK
| CLOBBERS: D0,D1,A0
| Called during boot.
InitRgn:
        MOVE    D0,18(A1)                       | INSTALL MINH
        MOVE    D1,20(A1)                       | SAVE VERT
        MOVE    D2,22(A1)                       | INSTALL LEFTH
        MOVE.L  A0,(A1)                         | state.rgnPtr := A0
        MOVE    #-0x7FFF,14(A1)                 | state.thisV := -32767 (init)
        MOVE    2(A0),16(A1)                    | state.nextV := rgn first vert
        LEA.L     10(A0),A0                     | POINT TO FIRST DATA
        MOVE.L  A0,4(A1)                        | INIT DATAPTR
        MOVE.L  (SP)+,A0                        | NEXTHOR: GET LEFT COORD
        SUB     D2,D1                           | CALC BUFFER WIDTH IN DOTS
        LSR     #0x5,D1                         | div by 32 dots-per-long - 1
        MOVE    D1,12(A1)                       | GET RIGHT COORD
INITRGN_CLRLOOP:
        CLR.L   -(SP)                           | ALLOCATE AND CLEAR BUFFER
        DBRA    D1,INITRGN_CLRLOOP              | loop until full scanbuf
        MOVE.L  SP,8(A1)                        | REMEMBER BUFFER START
        JMP     (A0)                            | RTS

| ----------------------------------------------------
| RETURN QUICKLY IF SCANBUF IS ALREADY CURRENT.

| .PROC SEEKRGN,0
| .REF MaskTab
| ------------------------------------------------------------------
| SeekRgn(rgnState,vert);
| ROUTINE TO PLAY BACK A REGION FORWARD OR BACKWARD UNTIL ITS SCAN
| BUFFER CONTAINS THE BITMAP FOR THE GIVEN VERTICAL COORDINATE.
| INPUTS: A1 POINTS TO A REGION STATE RECORD
| DO CONTAINS THE DESIRED VERTICAL COORD
| OUTPUTS: UPDATES THISV, NEXTV, DATAPTR, AND SCANBUF^ OF STATE RECORD
| D1-->1 IF CHANGE, 0 IF NO CHANGE. (Z-FLAG SET IF NO CHANGE)
| CLOBBERS: A0,D1.
| Called during boot (1,767 times in 30s trace).
SeekRgn:
        CMP     16(A1),D0                       | IS DESIRED VERT >= NEXTV ?
        BGE.B   SEEKRGN_CLRLP_CONT              | YES, BUMP DOWNWARD
        CMP     14(A1),D0                       | IS DESIRED VERT < CURRENT VERT ?
        BLT.B   SEEKRGN_CONT                    | backward seek: rewind
        CLR     D1                              | ELSE REPORT NO CHANGES
        RTS                                     | AND RETURN
SEEKRGN_CONT:
        MOVE.L  8(A1),A0                        | POINT TO SCANBUF
        MOVE    12(A1),D1                       | GET BUFFER SIZE
SEEKRGN_CLRLP:
        CLR.L   (A0)+                           | CLEAR A LONG
        DBRA    D1,SEEKRGN_CLRLP                | LOOP ENTIRE SCANBUF
        MOVE.L  (A1),A0                         | A0 := state.rgnPtr (rewind)
        MOVE    2(A0),16(A1)                    | state.nextV := rgn first vert
        MOVE    #-0x7FFF,14(A1)                 | state.thisV := -32767
        LEA.L     10(A0),A0                     | POINT TO START OF REGION DATA
        MOVE.L  A0,4(A1)                        | RESET DATAPTR
        CMP     16(A1),D0                       | IS DESIRED VERT >= NEXTV ?
        BLT.W   SEEKRGN_DONE                    | NO, QUIT
SEEKRGN_CLRLP_CONT:
        MOVEM.L D0-D6/A2-A3,-(SP)               | SAVE REGS
        MOVE    D0,D2                           | SAVE VERT
        MOVE.L  4(A1),A2                        | POINT TO VERT COORD
SEEKRGN_CLRLP_CONT_2:
        MOVE    (A2)+,14(A1)                    | UPDATE CURRENT VERT
| -------------------------------------------------
| GET LEFT AND RIGHT HORIZ COORDS
| AND TRIM AGAINST MINH AND MAXH
| Called during boot.
SEEKRGN_NEXTHOR:
        MOVE    (A2)+,D3                        | GET LEFT COORD
        CMPI    #0x7FFF,D3                      | is left horiz end marker (32767)?
        BEQ.B   DONE1                           | YES, QUIT
        MOVE    (A2)+,D4                        | GET RIGHT COORD
        CMP     18(A1),D4                       | IS RIGHT <= MINH ?
        BLE.B   SEEKRGN_NEXTHOR                 | YES, IGNORE ON LEFT
        CMP     20(A1),D3                       | IS LEFT >= MAXH ?
        BGE.B   SEEKRGN_NEXTHOR                 | YES, IGNORE ON RIGHT
        CMP     18(A1),D3                       | IS LEFT < MINH ?
        BGE.B   SEEKRGN_NEXTHOR_CONT            | NO, CONTINUE
        MOVE    18(A1),D3                       | YES, TRIM LEFT
SEEKRGN_NEXTHOR_CONT:
        CMP     20(A1),D4                       | IS RIGHT > MAXH ?
        BLE.B   SEEKRGN_NEXTHOR_CONT_2          | NO, CONTINUE
        MOVE    20(A1),D4                       | YES, TRIM RIGHT
SEEKRGN_NEXTHOR_CONT_2:
        SUB     22(A1),D3                       | MAKE COORDS REL TO BUFFER
        SUB     22(A1),D4                       | right relative to BUFLEFT
        MOVE    D3,D0                           | D0 := left for BitMask
        JSR     BitMask(PC)                     | compute right-pixel mask
        MOVE    D0,D5                           | D5 := left mask result
        MOVE    D4,D0                           | D0 := right for LeftMask
        JSR     LeftMask(PC)                    | compute left-pixel mask
        MOVE    D0,D6                           | D6 := right mask result
        LSR     #0x4,D3                         | left horiz / 16 (word index)
        MOVE.L  8(A1),A3                        | COPY BUFSTART
        ADDA.W  D3,A3                           | advance bufPtr by word index
        ADDA.W  D3,A3                           | INIT BUFPTR TO LEFTWORD
        LSR     #0x4,D4                         | right horiz / 16 (word index)
        SUB     D3,D4                           | WORDCOUNT:=RIGHTWORD-LEFTWORD
        BGT.B   NOTIN1                          | BR IF NOT ALL IN ONE
        AND     D5,D6                           | COMBINE LEFT AND RIGHT MASKS
        EOR     D6,(A3)                         | XOR COMBINATION INTO BUFFER
        BRA.B   SEEKRGN_NEXTHOR                 | GO FOR MORE DH'S THIS SCAN
NOTIN1:
        EOR     D5,(A3)+                        | XOR LEFTMASK INTO BUFFER
        BRA.B   INVLONG_CONT                    | SEE IF ANY FULL WORDS
INVLONG:
        NOT.L   (A3)+                           | (A3)+ = ~(A3)+
INVLONG_CONT:
        SUBQ.W  #0x2,D4                         | decrement word count by 2 (long)
        BGT.B   INVLONG                         | YES, AT LEAST 2
        BLT.B   ENDWORD                         | NO, FINISH UP LAST WITH MASK
        NOT     (A3)+                           | (A3)+ = ~(A3)+
ENDWORD:
        EOR     D6,(A3)                         | XOR RIGHTMASK INTO BUFFER
        BRA.B   SEEKRGN_NEXTHOR                 | GO FOR MORE DH'S THIS SCAN
DONE1:
        MOVE.L  A2,4(A1)                        | GET NEXT VERT IN A
        MOVE    (A2),16(A1)                     | UPDATE NEXT VERT
        CMP     16(A1),D2                       | IS DESIRED VERT >= NEXTV ?
        BGE.B   SEEKRGN_CLRLP_CONT_2            | YES, BUMP DOWN SOME MORE
        MOVEM.L (SP)+,D0-D6/A2-A3               | RESTORE REGS
SEEKRGN_DONE:
        MOVE    #0x1,D1                         | return D1=1 (changes happened)
        RTS                                     | AND RETURN
