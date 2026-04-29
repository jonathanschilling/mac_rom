| ------------------------------------------------------------------
|
| --> SORTPOINTS.TEXT
|
| Routines to sort inversion points and cull duplicates.
|

| .PROC SortPoints
| -------------------------------------------------------------
|
| PROCEDURE SortPoints(ptBuf: PointsPtr; ptCount: INTEGER);
|
| PERFORMS A NON-RECURSIVE QUICKSORT ON AN ARRAY OF POINTS
| TO PUT THEM IN INCREASING VERT.HORIZ ORDER.
|
| RE-WROTE 5 SEPT 83 TO CUT DOWN WORST CASE STACK USAGE
|
| See Algorithms + Data Structures = Programs, p.80
|
| A6 OFFSETS OF PARAMETERS AFTER LINK:
|
| Called during boot.
SortPoints:
.set PARAMSIZE, 6                               | TOTAL BYTES OF PARAMS
.set PTBUF, PARAMSIZE+8-4                       | LONG
.set PTCOUNT, PTBUF-2                           | WORD

        LINK    A6,#0                           | NO LOCAL VARIABLES
        MOVEM.L D3-D4/A2-A4,-(SP)               | SAVE REGS
        MOVE.L  0xA(A6),A3                      | LEFTPTR:=START OF PT ARRAY
        MOVE    A3,D3                           | COPY LEFTPTR LOW BITS
        ANDI    #0x3,D3                         | SET UP LOBITS FOR SORT
        CLR.L   D0                              | CLEAR FOR WORD LOAD
        MOVE    0x8(A6),D0                      | GET PTCOUNT
        BLE.B   SORTPOINTS_GOHOME               | DO NOTHING IF NO POINTS
        LSL.L   #2,D0                           | QUAD PTCOUNT FOR BYTES
        MOVE.L  A3,A4                           | COPY LEFTPTR
        ADD.L   D0,A4                           | ADD TO DSTSTART
        SUBQ.W  #0x4,A4                         | RIGHTPTR:=DSTEND-4
        MOVE.L  SP,D4                           | REMEMBER STACK MARKER
        MOVEM.L A3-A4,-(SP)                     | PUSH LEFTPTR AND RIGHTPTR
SORTPOINTS_LOOP:
        MOVEM.L (SP)+,A3-A4                     | POP LEFTPTR AND RIGHTPTR
SPLIT:
        MOVE.L  A3,A1                           | IPTR := LEFTPTR
        MOVE.L  A4,A2                           | JPTR := RIGHTPTR

|
| CALC MIDPTR AND MIDPT
|
        MOVE.L  A3,D0                           | ADD LEFTPTR
        ADD.L   A4,D0                           | AND RIGHTPTR
        ROXR.L  #1,D0                           | THEN DIVIDE BY 2 FOR MIDPTR
        ANDI    #-0x4,D0                        | TRUNC TO MULTIPLE OF 4 BYTES
        OR      D3,D0                           | OR IN LOBITS FOR POINT BOUNDARY
        MOVE.L  D0,A0                           | GET MIDPTR INTO A-REG
        MOVE    0x2(A0),D1                      | GET MIDPT.H
        MOVE    (A0),D2                         | AND MIDPT.V

| SCAN
|
| WHILE IPTR^ < MIDPT DO BUMP IPTR TO RIGHT
|
| Called during boot.
SPLIT_RETRY:
        BRA.B   SPLIT_LOOP                      | GO TO LOOP START

| ----------------------------------------------------------
|
| SPLIT_NEXT
|
| Called during boot.
SPLIT_NEXT:
        ADDQ.W  #0x4,A1                         | BUMP IPTR TO RIGHT
SPLIT_LOOP:
        CMP     (A1),D2                         | IS MIDPT.V > IPTR^.V ?
        BGT.B   SPLIT_NEXT                      | YES, BUMP SOME MORE
        BLT.B   THREE                           | BR IF DONE WITH IPTR.
        CMP     0x2(A1),D1                      | IF SAME VERT, LOOK AT HORIZ
        BGT.B   SPLIT_NEXT                      | KEEP BUMPING IF MIDPT.H > IPTR^.H

| THREE

|
| WHILE JPTR^ > MIDPT DO BUMP JPTR TO LEFT
|
| Called during boot.
THREE:
        BRA.B   SPLIT_LOOP_2                    | GO TO LOOP START

| ----------------------------------------------------------
|
| FOUR
|
| Called during boot.
FOUR:
        SUBQ.W  #0x4,A2                         | BUMP JPTR TO LEFT
SPLIT_LOOP_2:
        CMP     (A2),D2                         | IS MIDPT.V < JPTR^.V ?
        BLT.B   FOUR                            | YES, BUMP SOME MORE
        BGT.B   SPLIT_DONE_2                    | BR IF DONE BUMPING JPTR
        CMP     0x2(A2),D1                      | IF SAME VERT, LOOK AT HORIZ
        BLT.B   FOUR                            | KEEP BUMPING IF MIDPT.H < JPTR^.H

| SIX

|
| if IPtr <= JPtr then swap IPtr^ and JPtr^, and bump both pointers
|
| Called during boot.
SPLIT_DONE_2:
        CMP.L   A2,A1                           | IS IPTR > JPTR ?
        BGT.B   SORTPOINTS_NOSWAP               | YES, ALL DONE
        MOVE.L  (A1),D0                         | READ IPTR^ INTO TEMP
        MOVE.L  (A2),(A1)                       | COPY JPTR^ TO IPTR^
        MOVE.L  D0,(A2)                         | SWAP POINTS
        ADDQ.W  #0x4,A1                         | BUMP IPTR TO RIGHT
        SUBQ.W  #0x4,A2                         | BUMP JPTR TO LEFT

|
| repeat until this partitioning is complete, IPtr > JPtr
|
| Called during boot.
SORTPOINTS_NOSWAP:
        CMPA.L  A2,A1                           | NOSWAP: IS IPTR > JPTR ?
        BLS.B   SPLIT_RETRY                     | NO, LOOP AGAIN

|
| IF i < right then stack request to sort right partition
|
        CMPA.L  A4,A1                           | IS IPTR < RIGHTPTR ?
        BCC.B   SORTPOINTS_RIGHTOK              | YES, CONTINUE
        MOVEM.L A1/A4,-(SP)                     | NO, PUSH IPTR,RIGHTPTR
SORTPOINTS_RIGHTOK:
        MOVE.L  A2,A4                           | RIGHTOK: RIGHTPTR := JPTR
        CMPA.L  A4,A3                           | IS LEFTPTR >= RIGHTPTR ?
        BCS.B   SPLIT                           | NO, PARTITION AGAIN
        CMPA.L  D4,SP                           | IS STACK EMPTY YET ?
        BNE.B   SORTPOINTS_LOOP                 | NO, LOOP FOR MORE
SORTPOINTS_GOHOME:
        MOVEM.L (SP)+,D3-D4/A2-A4               | GOHOME: RESTORE REGS
        UNLK    A6                              | RESTORE A6
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDQ.W  #0x6,SP                         | STRIP 6 BYTES OF PARAMS
        JMP     (A0)                            | RETURN TO CALLER

| .PROC CullPoints,2
| -------------------------------------------------------------
|
| PROCEDURE CullPoints(ptBuf: PointsPtr; VAR ptCount: INTEGER);
|
| CANCEL ANY DUPLICATE PAIRS OF POINTS IN AN ARRAY OF POINTS.
|
|
| A6 OFFSETS OF PARAMETERS AFTER LINK:
|
| PARAMSIZE .EQU 8
| PTBUF .EQU PARAMSIZE+8-4 ;LONG
| PTCOUNT .EQU PTBUF-4 ;LONG, VAR
| Called during boot.
CullPoints:
.set PARAMSIZE, 8                               | TOTAL BYTES OF PARAMS
.set PTBUF, PARAMSIZE+8-4                       | LONG
.set PTCOUNT, PTBUF-4                           | LONG, VAR

        LINK    A6,#0                           | NO LOCAL VARIABLES
        MOVEM.L D0-D7/A1-A5,-(SP)               | SAVE REGS
        MOVE.L  0x8(A6),A0                      | GET VAR ADDR OF PTCOUNT
        MOVE    (A0),D0                         | GET PTCOUNT
        BLE     CULLPOINTS_GOHOME               | DO NOTHING IF NO POINTS
        MOVE.L  0xC(A6),A1                      | SRCPTR:=START PTR
        MOVE.L  A1,A3                           | COPY START
        EXT.L   D0                              | CLEAR HI WORD
        LSL.L   #2,D0                           | QUAD PTCOUNT FOR BYTES
        ADD.L   D0,A3                           | ADD TO START
        SUBQ.W  #0x4,A3                         | LAST POINT IS AT END-4
        MOVE.L  A1,D5                           | SAVE START FOR LATER
        MOVE.L  A1,A2                           | DSTPTR:=START
        BRA.B   CULLPOINTS_WHILE1               | GO TO LOOP START

| ----------------------------------------------------------
|
| DELETE
|
| Called during boot.
DELETE:
        ADDQ.W  #0x4,A1                         | SKIP OVER BOTH SRC POINTS
        BRA.B   CULLPOINTS_WHILE1               | GO TO LOOP START

| ----------------------------------------------------------
|
| CULLPOINTS_MORE1
|
| Called during boot.
CULLPOINTS_MORE1:
        MOVE.L  (A1)+,D0                        | MORE1: GET CURRENT SRC POINT
        CMP.L   (A1),D0                         | IS IT SAME AS NEXT ?
        BEQ.B   DELETE                          | YES, DELETE BOTH
        MOVE.L  D0,(A2)+                        | NO, COPY TO DST
CULLPOINTS_WHILE1:
        CMP.L   A3,A1                           | WHILE1: IS SRCPTR < LASTPTR ?
        BLT.B   CULLPOINTS_MORE1                | YES, GO FOR MORE
        BGT.B   CULLPOINTS_DONE                 | BR IF DONE
        MOVE.L  (A1)+,(A2)+                     | FINISH UP LAST POINT
CULLPOINTS_DONE:
        MOVE.L  A2,D0                           | DONE: GET DST PTR
        SUB.L   D5,D0                           | SUBTRACT START PTR
        LSR     #2,D0                           | DIV BY 4 FOR PTCOUNT
        MOVE.L  0x8(A6),A0                      | GET VAR ADDR
        MOVE    D0,(A0)                         | UPDATE PTCOUNT TO REFLECT DELETIONS
CULLPOINTS_GOHOME:
        MOVEM.L (SP)+,D0-D7/A1-A5               | GOHOME: RESTORE REGS
        UNLK    A6                              | RESTORE A6
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDQ.W  #0x8,SP                         | STRIP 8 BYTES OF PARAMS
        JMP     (A0)                            | RETURN TO CALLER


