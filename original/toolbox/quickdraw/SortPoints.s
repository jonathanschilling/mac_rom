| ------------------------------------------------------------------
|
| --> SORTPOINTS.TEXT
|
| Routines to sort inversion points and cull duplicates.

SortPoints:
        LINK    A6,#0x0                         | NO LOCAL VARIABLES
        MOVEM.L D3-D4/A2-A4,-(SP)               | SAVE REGS
        MOVE.L  10(A6),A3                       | LEFTPTR:=START OF PT ARRAY
        MOVE    A3,D3                           | capture LO bits of LEFTPTR
        ANDI    #0x3,D3                         | SET UP LOBITS FOR SORT
        CLR.L   D0                              | clear hi word for unsigned ext
        MOVE    8(A6),D0                        | RIGHTOK: RIGHTPTR := JPTR
        BLE.W   SORTPOINTS_RIGHTOK_CONT         | DO NOTHING IF NO POINTS
        LSL.L   #0x2,D0                         | QUAD PTCOUNT FOR BYTES
        MOVE.L  A3,A4                           | A4 := DSTSTART
        ADDA.L  D0,A4                           | ADD TO DSTSTART
        SUBQ.W  #0x4,A4                         | RIGHTPTR:=DSTEND-4
        MOVE.L  SP,D4                           | REMEMBER STACK MARKER
        MOVEM.L A3-A4,-(SP)                     | PUSH LEFTPTR AND RIGHTPTR
SORTPOINTS_LOOP:
        MOVEM.L (SP)+,A3-A4                     | POPNXT: POP LEFTPTR AND RIGHTPTR
SPLIT:
        MOVE.L  A3,A1                           | jump via A0
        MOVE.L  A4,A2                           | JPTR := RIGHTPTR
        MOVE.L  A3,D0                           | ADD LEFTPTR
        ADD.L   A4,D0                           | AND RIGHTPTR
        ROXR.L  #0x1,D0                         | THEN DIVIDE BY 2 FOR MIDPTR
        ANDI    #-0x4,D0                        | TRUNC TO MULTIPLE OF 4 BYTES
        OR      D3,D0                           | OR IN LOBITS FOR POINT BOUNDARY
        MOVE.L  D0,A0                           | GET MIDPTR INTO A-REG
        MOVE    2(A0),D1                        | GET MIDPT.H
        MOVE    (A0),D2                         | AND MIDPT.V
SPLIT_RETRY:
        BRA.B   SPLIT_LOOP                      | jump to compare
SPLIT_NEXT:
        ADDQ.W  #0x4,A1                         | ONE: BUMP IPTR TO RIGHT
SPLIT_LOOP:
        CMP     (A1),D2                         | TWO: IS MIDPT.V > IPTR^.V ?
        BGT.B   SPLIT_NEXT                      | D2 > (A1): advance
        BLT.B   THREE                           | D2 < (A1): go to A2 scan
        CMP     2(A1),D1                        | IF SAME VERT, LOOK AT HORIZ
        BGT.B   SPLIT_NEXT                      | D1 > 2(A1): advance
THREE:
        BRA.B   SPLIT_LOOP_2                    | jump to compare
FOUR:
        SUBQ.W  #0x4,A2                         | FOUR: BUMP JPTR TO LEFT
SPLIT_LOOP_2:
        CMP     (A2),D2                         | FIVE: IS MIDPT.V < JPTR^.V ?
        BLT.B   FOUR                            | D2 < (A2): back up
        BGT.B   SPLIT_DONE_2                    | D2 > (A2): done
        CMP     2(A2),D1                        | IF SAME VERT, LOOK AT HORIZ
        BLT.B   FOUR                            | D1 < 2(A2): back up
SPLIT_DONE_2:
        CMPA.L  A2,A1                           | SIX: IS IPTR > JPTR ?
        BGT.B   SORTPOINTS_NOSWAP               | YES, ALL DONE
        MOVE.L  (A1),D0                         | NO, COPY TO DST
        MOVE.L  (A2),(A1)                       | SWAP POINTS step 2
        MOVE.L  D0,(A2)                         | SWAP POINTS step 3
        ADDQ.W  #0x4,A1                         | BUMP IPTR TO RIGHT
        SUBQ.W  #0x4,A2                         | BUMP JPTR TO LEFT
SORTPOINTS_NOSWAP:
        CMPA.L  A2,A1                           | NOSWAP: IS IPTR > JPTR ?
        BLS.B   SPLIT_RETRY                     | branch if <= (unsigned)
        CMPA.L  A4,A1                           | IS IPTR < RIGHTPTR ?
        BCC.W   SORTPOINTS_RIGHTOK              | YES, CONTINUE
        MOVEM.L A1/A4,-(SP)                     | NO, PUSH IPTR,RIGHTPTR
SORTPOINTS_RIGHTOK:
        MOVE.L  A2,A4                           | RIGHTPTR := JPTR
        CMPA.L  A4,A3                           | IS LEFTPTR >= RIGHTPTR ?
        BCS.B   SPLIT                           | NO, PARTITION AGAIN
        CMPA.L  D4,SP                           | IS STACK EMPTY YET ?
        BNE.B   SORTPOINTS_LOOP                 | NO, LOOP FOR MORE
SORTPOINTS_RIGHTOK_CONT:                        | jump via A0
        MOVEM.L (SP)+,D3-D4/A2-A4               | GOHOME: RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return PC
        ADDQ.W  #0x6,SP                         | strip PARAMSIZE bytes
        JMP     (A0)                            | RTS

| .PROC CullPoints,2
| -------------------------------------------------------------
| PROCEDURE CullPoints(ptBuf: PointsPtr; VAR ptCount: INTEGER);
| CANCEL ANY DUPLICATE PAIRS OF POINTS IN AN ARRAY OF POINTS.
| A6 OFFSETS OF PARAMETERS AFTER LINK:
| PARAMSIZE .EQU 8
| PTBUF .EQU PARAMSIZE+8-4 ;LONG
| PTCOUNT .EQU PTBUF-4 ;LONG, VAR
| Called during boot.
CullPoints:
        LINK    A6,#0x0                         | NO LOCAL VARIABLES
        MOVEM.L D0-D7/A1-A5,-(SP)               | SAVE REGS
        MOVE.L  8(A6),A0                        | GET VAR ADDR OF PTCOUNT
        MOVE    (A0),D0                         | GET PTCOUNT
        BLE.W   CULLPOINTS_GOHOME               | DO NOTHING IF NO POINTS
        MOVE.L  12(A6),A1                       | SRCPTR:=START PTR
        MOVE.L  A1,A3                           | COPY START
        EXT.L    D0                             | CLEAR HI WORD
        LSL.L   #0x2,D0                         | QUAD PTCOUNT FOR BYTES
        ADDA.L  D0,A3                           | ADD TO START
        SUBQ.W  #0x4,A3                         | LAST POINT IS AT END-4
        MOVE.L  A1,D5                           | SAVE START FOR LATER
        MOVE.L  A1,A2                           | YES, MINH:=PT.H
        BRA.B   CULLPOINTS_WHILE1               | LOOP FOR MORE
DELETE:
        ADDQ.W  #0x4,A1                         | SKIP OVER BOTH SRC POINTS
        BRA.B   CULLPOINTS_WHILE1               | GO TO LOOP START
CULLPOINTS_MORE1:
        MOVE.L  (A1)+,D0                        | YES, MAXH:=PT.H
        CMP.L   (A1),D0                         | IS IT SAME AS NEXT ?
        BEQ.B   DELETE                          | YES, DELETE BOTH
        MOVE.L  D0,(A2)+                        | NO, COPY TO DST
CULLPOINTS_WHILE1:
        CMPA.L  A3,A1                           | IS SRCPTR < LASTPTR ?
        BLT.B   CULLPOINTS_MORE1                | YES, GO FOR MORE
        BGT.B   CULLPOINTS_DONE                 | past end, exit loop
        MOVE.L  (A1)+,(A2)+                     | FINISH UP LAST POINT
CULLPOINTS_DONE:
        MOVE.L  A2,D0                           | GET DST PTR
        SUB.L   D5,D0                           | SUBTRACT START PTR
        LSR     #0x2,D0                         | DIV BY 4 FOR PTCOUNT
        MOVE.L  8(A6),A0                        | GET VAR ADDR
        MOVE    D0,(A0)                         | UPDATE PTCOUNT
CULLPOINTS_GOHOME:
        MOVEM.L (SP)+,D0-D7/A1-A5               | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return PC
        ADDQ.W  #0x8,SP                         | strip PARAMSIZE bytes
        JMP     (A0)                            | RTS
