| ------------------------------------------------
|
| A6 OFFSETS OF PARAMETERS AFTER LINK:
|

| .PROC PUTRGN,4
| .REF SETSIZE
| ----------------------------------------------------------------
|
| PROCEDURE PutRgn(Rgn: RgnHandle; bufHandle: Handle; VAR index,size: INTEGER);
|
| Expands a region out to an array of inversion points.
|
PutRgn:
.set PARAMSIZE, 16                              | TOTAL SIZE OF PARAMETERS
.set RGNHANDLE, PARAMSIZE+8-4                   | LONG,RGNHANDLE
.set BUFHANDLE, RGNHANDLE-4                     | LONG, HANDLE
.set INDEX, BUFHANDLE-4                         | LONG, VAR
.set SIZE, INDEX-4                              | LONG, VAR

        LINK    A6,#0                           | NO LOCAL VARS
        MOVEM.L D7/A2-A4,-(SP)                  | SAVE REGS

| -------------------------------------------------------
|
| EXPAND BUF TO FIT WORST CASE BYTESNEEDED = RGNSIZE * 2
|
        MOVE.L  0x10(A6),A4                     | GET BUFHANDLE
        MOVE.L  0x14(A6),A3                     | GET RGNHANDLE
        MOVE.L  0xC(A6),A2                      | POINT TO CURRENT INDEX

| -------------------------------------------------------
|
        MOVE.L  (A3),A0                         | DE-REFERENCE RGN
        MOVE    (A0),D7                         | GET RGNSIZE
        ADD     D7,D7                           | TIMES 2
        ADD     (A2),D7                         | ADD CURRENT INDEX
        MOVE.L  0x8(A6),A1                      | POINT TO SIZE
        CMP     (A1),D7                         | IS REQUIRED > CURRENT SIZE ?
        BLE.B   NOGROW                          | NO, CONTINUE
        ADDI    #0x100,D7                       | GROW IN CHUNKS OF 256 BYTES
        MOVE    D7,(A1)                         | UPDATE CURRENT SIZE
        MOVE.L  A4,-(SP)                        | PUSH BUFHANDLE
        MOVE    D7,-(SP)                        | PUSH NEW SIZE
        JSR     SetHSize(PC)                    | MAKE ROOM IN BUF
        MOVE.L  (A3),A0                         | RE-DEREFERENCE RGNHANDLE
        MOVE.L  0xC(A6),A2                      | GET ADDR OF INDEX AGAIN
NOGROW:
        MOVE.L  (A4),A1                         | DE-REFERENCE BUFHANDLE
        ADD     (A2),A1                         | ADD INDEX TO BUFPTR
        CMPI    #0xA,(A0)                       | IS REGION RECTANGULAR? (SIZE 10)
        BNE.B   PUTRGN_NOTRECT                  | NO, CONTINUE
        ADDQ.W  #0x2,A0                         | YES, SKIP RGNSIZE TO BBOX TOPLEFT
        MOVE.L  (A0)+,(A1)+                     | COPY TOPLEFT
        MOVE.L  (A0)+,(A1)+                     | COPY BOTRIGHT
        BRA.B   PUTRGN_DONE                     | UPDATE INDEX AND QUIT

| ----------------------------------------------------------
|
| PUTRGN_NOTRECT
|
PUTRGN_NOTRECT:
        LEA.L   RGNDATA(A0),A0                  | POINT TO TOP VERT IN RGN
PUTRGN_NXTVERT:
        MOVE.L  (A0)+,D7                        | NXTVERT: GET VERT AND HORIZ COORDS
NXTHOR:
        MOVE.L  D7,(A1)+                        | PUT LEFT POINT TO DST
        MOVE    (A0)+,D7                        | GET HORIZ COORD
        MOVE.L  D7,(A1)+                        | PUT RIGHT POINT TO DST
        MOVE    (A0)+,D7                        | GET NEXT HORIZ COORD
        CMPI    #0x7FFF,D7                      | IS HORIZONTAL COORD END OF SCAN FLAG?
        BNE.B   NXTHOR                          | NO, GO FOR MORE
        CMPI    #0x7FFF,(A0)                    | IS NEXT VERT COORD END OF REGION FLAG?
        BNE.B   PUTRGN_NXTVERT                  | NO, LOOP FOR MORE
PUTRGN_DONE:
        SUB.L   (A4),A1                         | DONE: CALC DSTPTR - DSTSTART
        MOVE    A1,(A2)                         | UPDATE VAR INDEX
        MOVEM.L (SP)+,D7/A2-A4                  | GOHOME: RESTORE REGISTERS
        UNLK    A6                              | DESTROY A6 STACK FRAME
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS FOR MANUAL RTS
        ADDA    #0x10,SP                        | STRIP 16 BYTES OF PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER


