| .PROC PACKRGN,3
| .REF SETSIZE
| -----------------------------------------------------------------
|
| PROCEDURE PackRgn(srcHandle: Handle; nPoints: INTEGER; dstRgn: RgnHandle);
|
| Converts a sorted array of inversion points into a region.
| Calls storage allocator to make more room and trim result to minimum size.
|
| OUTPUT IS IN THE FOLLOWING FORM:
|
| RGNSIZE
| RGNBBOX
| V H .. H 32767
| V=32767
|
| A6 OFFSETS OF PARAMETERS AFTER LINK:
|
| Called during boot (7,415 times in 30s trace).
PackRgn:
        LINK    A6,#-0x8                        | ALLOCATE LOCAL VARIABLES
.set PARAMSIZE, 10                              | TOTAL BYTES OF PARAMS
.set SRCHANDLE, PARAMSIZE+8-4                   | LONG
.set NPOINTS, SRCHANDLE-2                       | INTEGER
.set DSTRGN, NPOINTS-4                          | LONG, HANDLE

| -------------------------------------------------------
|
| A6 OFFSETS OF LOCAL VARIABLES AFTER LINK:
|
.set BBOX, -8                                   | RECTANGLE
.set VARSIZE, BBOX                              | SIZE OF LOCAL VARIABLES

        MOVEM.L D0-D7/A1-A4,-(SP)               | SAVE REGS
        MOVE.L  0xE(A6),A4                      | GET SRC HANDLE
        MOVE.L  0x8(A6),A3                      | GET DST RGNHANDLE
        MOVE    0xC(A6),D6                      | GET NUMBER OF POINTS
        MOVE.L  (A3),A1                         | DE-REFERENCE DSTRGN
        MOVE    (A1),D5                         | GET CURRENT RGNSIZE
        MOVE.L  (A4),A0                         | DE-REFERENCE SRCHANDLE

| ------------------------------------------------------------------------
|
| CHECK NPOINTS TO SPECIAL CASE EMPTY AND RECTANGULAR REGIONS.
|
        MOVEQ   #10,D7                          | INIT RGNSIZE TO EMPTY RGN SIZE
        CLR.L   -0x8(A6)                        | INIT BOUNDING BOX TO EMPTY
        CLR.L   -0x4(A6)                        | INIT BOTRIGHT OF BOUNDING BOX
        CMPI    #0x4,D6                         | HOW MANY POINTS IN SOURCE ?
        BGT.B   PACKRGN_NO                      | MORE THAN 4, NOT RECTANGULAR
        BLT.B   PACKRGN_DONE                    | LESS THAN 4, EMPTY REGION
        MOVE.L  (A0),-0x8(A6)                   | GET TOPLEFT OF BOUNDING BOX
        MOVE.L  0xC(A0),-0x4(A6)                | GET BOTRIGHT OF BOUNDING BOX
        BRA.B   PACKRGN_DONE                    | INSTALL RGNSIZE AND BBOX AND QUIT

| ----------------------------------------------------------
|
| PACKRGN_NO
|
| Called during boot (7,410 times in 30s trace).
PACKRGN_NO:
        MOVE    (A0),-0x8(A6)                   | BBOX TOP:=FIRST POINT.V
        MOVE    0x2(A0),D1                      | INIT MINH TO FIRST HORIZ

| ------------------------------------------------------------------------
|
| MORE THAN FOUR POINTS, NON-RECTANGULAR. SCAN FOR BBOX LEFT AND RIGHT.
|
        MOVE    D1,D2                           | INIT MAXH TO FIRST HORIZ ALSO
        MOVE    D6,D3                           | GET NUMPER OF POINTS IN SRC
PACKRGN_LOOP:
        SUBQ.W  #0x1,D3                         | ANY POINTS LEFT ?
        BLT.B   ENDSCAN                         | NO, QUIT SCANNING
        MOVE.L  (A0)+,D0                        | YES, GET NEXT POINT
        CMP     D1,D0                           | IS PT.H < MINH ?
        BGE.B   PACKRGN_NO_2                    | NO, CONTINUE
        MOVE    D0,D1                           | YES, MINH:=PT.H
        BRA.B   PACKRGN_LOOP                    | LOOP FOR MORE

| ----------------------------------------------------------
|
| PACKRGN_NO_2
|
| Called during boot (177,703 times in 30s trace).
PACKRGN_NO_2:
        CMP     D2,D0                           | IS PT.H > MAXH ?
        BLE.B   PACKRGN_LOOP                    | NO, GO FOR NEXT
        MOVE    D0,D2                           | YES, MAXH:=PT.H
        BRA.B   PACKRGN_LOOP                    | GO FOR NEXT

| ----------------------------------------------------------
|
| ENDSCAN
|
| Called during boot (7,410 times in 30s trace).
ENDSCAN:
        MOVE    D1,-0x6(A6)                     | BBOX LEFT:=MINH
        MOVE    D2,-0x2(A6)                     | BBOX RIGHT:=MAXH
        MOVE    -0x4(A0),-0x4(A6)               | BBOX BOTTOM:=LAST POINT.V

| ----------------------------------------------------------------
|
| EXPAND DSTRGN TO HOLD WORST CASE = 12 + 4*NPOINTS bytes.
|
        MOVEQ   #3,D5                           | INIT SIZE CALCULATION
        ADD     D6,D5                           | GET NPOINTS + 3
        LSL     #2,D5                           | TIMES 4
        MOVE.L  A3,-(SP)                        | PUSH DSTRGN
        MOVE    D5,-(SP)                        | PUSH NEW BYTECOUNT
        JSR     SetHSize(PC)                    | MAKE IT THAT BIG

| ----------------------------------------------------
|
| NEWLY DE-REFERENCE SRC AND DST HANDLES
|
        MOVE.L  (A4),A0                         | DE-REFERENCE SRC HANDLE
        MOVE.L  (A3),A1                         | DE-REFERENCE DSTRGN HANDLE
        ADD     D7,A1                           | SKIP OVER RGNSIZE & BBOX
        SUBQ.W  #0x1,D6                         | DBRA COUNT = NPOINTS - 1
        MOVE    (A0)+,D0                        | GET FIRST VERT COORD
        MOVE    #32767,D1                       | PREPARE CONSTANT 32767
        BRA.B   PACKRGN_START                   | GO TO LOOP START

| ----------------------------------------------------------
|
| NEXTPT
|
| Called during boot (170,308 times in 30s trace).
NEXTPT:
        CMP     (A0)+,D0                        | SAME VERT COORD ?
        BEQ.B   VSAME                           | YES, CONTINUE
        MOVE    D1,(A1)+                        | PUT END OF ROW MARKER
        MOVE    -0x2(A0),D0                     | GET NEW VERT COORD
PACKRGN_START:
        MOVE    D0,(A1)+                        | START: PUT VERT COORD
VSAME:
        MOVE    (A0)+,(A1)+                     | PUT HORIZ COORD
        DBF     D6,NEXTPT                       | LOOP FOR ALL POINTS
        MOVE    D1,(A1)+                        | PUT END OF ROW MARKER
        MOVE    D1,(A1)+                        | PUT FINAL VERT = 32767
        MOVE.L  (A3),A0                         | DE-REFERENCE DSTRGN HANDLE
        SUB.L   A0,A1                           | SUBTRACT FROM DSTPTR
        MOVE    A1,D7                           | TO COMPUTE RGNSIZE

| --------------------------------------------------------
|
| INSTALL RGNSIZE AND RGNBBOX.
|
| Called during boot (7,415 times in 30s trace).
PACKRGN_DONE:
        MOVE.L  (A3),A0                         | DONE: DE-REFERENCE DSTRGN HANDLE
        MOVE    D7,(A0)+                        | INSTALL RGNSIZE
        MOVE.L  -0x8(A6),(A0)+                  | INSTALL BOUNDING BOX TOPLEFT
        MOVE.L  -0x4(A6),(A0)+                  | AND BOTRIGHT

| --------------------------------------------------------
|
| TRIM DSTRGN TO EXACT SIZE IF IT ISN'T ALREADY.
|
        CMP     D7,D5                           | IS IT ALREADY THE RIGHT SIZE ?
        BEQ.B   PACKRGN_SIZEOK                  | YES, SKIP
        MOVE.L  A3,-(SP)                        | PUSH DSTRGN HANDLE
        MOVE    D7,-(SP)                        | PUSH NEW SIZE
        JSR     SetHSize(PC)                    | TRIM TO EXACT SIZE

| ------------------------------------------------------
|
| CLEAN UP THE STACK AND GO HOME.
|
| Called during boot (7,415 times in 30s trace).
PACKRGN_SIZEOK:
        MOVEM.L (SP)+,D0-D7/A1-A4               | SIZEOK: RESTORE REGISTERS
        UNLK    A6                              | UNLINK LOCAL VARIABLES
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDA    #0xA,SP                         | STRIP 10 BYTES OF PARAMS
        JMP     (A0)                            | RETURN TO CALLER


