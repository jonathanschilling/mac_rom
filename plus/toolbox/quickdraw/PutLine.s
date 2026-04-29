| -----------------------------------------------------------
|
| --> PUTLINE.TEXT
|
| Decompose a line segment into a list of inversion points.
|

| .PROC PUTLINE,5
| .REF SETSIZE
| ------------------------------------------------------------------
|
| PROCEDURE PutLine(pt1,pt2: Point; dst: Handle; VAR index,bufMax: INTEGER);
|
| INVERSION POINTS FOR A LINE SEGMENT
|
| SP OFFSETS OF PARAMETERS:
|
PutLine:
.set PARAMSIZE, 20                              | TOTAL SIZE OF PARAMETERS
.set PT1, PARAMSIZE+4-4                         | LONG, POINT (VALUE)
.set PT2, PT1-4                                 | LONG, POINT (VALUE)
.set BUF, PT2-4                                 | LONG, HANDLE
.set INDEX, BUF-4                               | LONG, (VAR)
.set BUFMAX, INDEX-4                            | LONG, (VAR)

        MOVEM.L D3-D7/A2-A4,-(SP)               | SAVE REGS, 8*4 ==> 32
        MOVE    0x36(SP),D2                     | Load pt1.h to check for vertical line
        MOVE    0x32(SP),D4                     | Load pt2.h to check for vertical line

| -----------------------------------------------------
|
| IF LINE IS VERTICAL, IGNORE IT.
|
        CMP     D2,D4                           | IS THIS A VERTICAL LINE ?
        BEQ     PUTLINE_GOHOME                  | YES, IGNORE IT

| ------------------------------------------------------
|
| CALC BYTESNEEDED = 8 * ( Min(ABS(dh),ABS(dv)) + 1)
|
        MOVE    D2,D0                           | GET H1
        SUB     D4,D0                           | SUBTRACT H2
        BPL.B   DHPOS                           | BR IF DH POS
        NEG     D0                              | ELSE TAKE ABSOLUTE VALUE
DHPOS:
        MOVE    0x34(SP),D1                     | Load pt1.v coordinate to calculate dv
        SUB     0x30(SP),D1                     | Subtract pt2.v from pt1.v to find dv
        BPL.B   DVPOS                           | BR IF DV POS
        NEG     D1                              | ELSE TAKE ABSOLUTE VALUE
DVPOS:
        CMP     D1,D0                           | IS DH <= DV ?
        BLE.B   DVPOS_OK                        | YES, CONTINUE
        MOVE    D1,D0                           | NO, PUT MIN(DH,DV) INTO D0
DVPOS_OK:
        ADDQ.W  #0x1,D0                         | Add 1 to min(dh,dv) to include endpoints
        LSL     #3,D0                           | TIMES EIGHT FOR BYTESNEEDED
        MOVE.L  0x2C(SP),A3                     | Load destination point buffer handle
        MOVE.L  0x28(SP),A4                     | Load pointer to buffer index variable

| -----------------------------------------------------
|
| GROW POINT BUFFER AS NECESSARY TO HOLD BYTESNEEDED
|
        ADD     (A4),D0                         | NEWSIZE := INDEX + BYTESNEEDED
        MOVE.L  0x24(SP),A0                     | Load pointer to bufMax to check limits
        CMP     (A0),D0                         | DO WE HAVE TO GROW DSTBUF ?
        BLE.B   DVPOS_NO                        | NO, CONTINUE
        ADDI    #0x200,D0                       | Expand buffer size by 512 bytes chunks
        MOVE    D0,(A0)                         | UPDATE NEW BUFMAX
        MOVE.L  A3,-(SP)                        | PUSH DSTBUF HANDLE
        MOVE    D0,-(SP)                        | PUSH NEW BUFMAX
        JSR     SetHSize(PC)                    | MAKE THE BUFFER BIGGER
        MOVE    0x36(SP),D2                     | Restore pt1.h clobbered by SetHSize

| NOGROW
DVPOS_NO:
        MOVE.L  (A3),A3                         | DE-REFERENCE DSTHANDLE
        ADD     (A4),A3                         | ADD INDEX TO BUFPTR
        MOVE    0x34(SP),D1                     | Load pt1.v for horizontal line check
        MOVE    0x30(SP),D3                     | Load pt2.v for horizontal line check

| -----------------------------------------------------
|
| IF LINE IS HORIZONTAL, PUT ITS TWO ENDPOINTS
|
        CMP     D1,D3                           | IS THIS A HORIZONTAL LINE ?
        BNE.B   PUTLINE_SLANTED                 | NO, BRANCH
        MOVE    D1,(A3)+                        | PUT V1 VERT COORD
        MOVE    D2,(A3)+                        | PUT H1 HORIZ COORD
        MOVE    D3,(A3)+                        | PUT V2 VERT COORD
        MOVE    D4,(A3)+                        | PUT H2 HORIZ COORD
        BRA.B   NOCHNG_EXIT                     | UPDATE INDEX AND QUIT

| ------------------------------------------------------
|
| LINE IS SLANTED. DIVIDE IT INTO HORIZONTAL SLABS
| AND PUT THE TWO ENDPOINTS OF EACH SLAB.
|
| START BY SORTING POINTS VERTICALLY.
|
PUTLINE_SLANTED:
        BGT.B   NOSWAP                          | SKIP IF ALREADY IN ORDER
        EXG     D1,D3                           | SORT POINTS BY VERTICAL
        EXG     D2,D4                           | SWAP HORIZ TO MATCH
NOSWAP:
        MOVE    D1,D6                           | INIT V TO TOPV

| ------------------------------------------------------------
|
| CALCULATE FIXED POINT SLOPE = FixRatio(dh,dv);
|
        CLR.L   -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE    D4,-(SP)                        | PUSH BOTTOM HORIZ
        SUB     D2,(SP)                         | CALC DH
        MOVE    D3,-(SP)                        | PUSH BOTTOM VERT
        SUB     D1,(SP)                         | CALC DV
        _FixRatio                               | CALC FIXED POINT SLOPE
        MOVE.L  (SP)+,D7                        | POP RESULT
        MOVE    D2,D1                           | Copy starting top horizontal position

| ---------------------------------------------------------
|
| SET UP STARTING HORIZ FIXED POINT.
|
        SWAP    D1                              | HORIZ.INT := TOP HORIZ
        MOVE    #-0x8000,D1                     | Initialize fixed-point fraction to 0.5

|
| ADJUST HORIZ DEPENDING ON SIGN AND MAGNITUDE OF SLOPE
|
        MOVE.L  D7,D0                           | COPY SLOPE
        ASR.L   #1,D0                           | CALC SLOPE/2
        ADD.L   D0,D1                           | HORIZ := HORIZ + SLOPE/2
        MOVE.L  #0x10000,D0                     | Load fixed-point value of 1.0 for bounds
        TST.L   D7                              | IS SLOPE NEG ?
        BMI.B   NOSWAP_OK                       | YES, CONTINUE
        CMP.L   D0,D7                           | IS SLOPE < ONE ?
        BGE.B   NOSWAP_NO                       | NO, CONTINUE
        ADD.L   D7,D1                           | ADD SLOPE TO LEFTEDGE
        BRA.B   NOSWAP_NO                       | CONTINUE

| ----------------------------------------------------------
|
| NOSWAP_OK
|
NOSWAP_OK:
        CMPI.L  #0xFFFF0000,D7                  | Is fixed-point slope >= -1.0?
        BGE.B   NOSWAP_NO                       | YES, CONTINUE
        ADD.L   D0,D1                           | YES, HORIZ := HORIZ + 1

| SLOPEOK

| ------------------------------------------------------
|
| FOR VERT:=TOPV TO BOTV-1 ADD SLOPE TO HORIZ AND PUT SLABS
|
NOSWAP_NO:
        MOVE    D2,D5                           | H:=TOPH
LOOP:
        SWAP    D1                              | GET HORIZ.INT INTO D1 LOWER
        CMP     D1,D5                           | HAS HORIZ.INT CHANGED ?
        BEQ.B   NOCHNG                          | NO, CONTINUE
        MOVE    D6,(A3)+                        | YES, PUT VERT COORD
        MOVE    D5,(A3)+                        | PUT OLD HORIZ COORD
        MOVE    D1,D5                           | Save current horizontal integer part
        MOVE    D6,(A3)+                        | PUT VERT COORD
        MOVE    D5,(A3)+                        | PUT NEW HORIZ COORD
NOCHNG:
        SWAP    D1                              | PUTBACK HORIZ.INT INTO D1 UPPER
        ADDQ.W  #0x1,D6                         | Advance vertical coordinate to next slab
        ADD.L   D7,D1                           | ADD SLOPE TO HORIZ
        CMP     D6,D3                           | IS VERT AT BOTTOM VERT YET ?
        BNE.B   LOOP                            | NO, GO FOR MORE

| -------------------------------------------------
|
| FINISH UP LAST SLAB
|
        CMP     D4,D5                           | IS OLDH = BOTTOM H ?
        BEQ.B   NOCHNG_EXIT                     | YES, CONTINUE
        MOVE    D6,(A3)+                        | NO, PUT VERT COORD
        MOVE    D5,(A3)+                        | PUT HORIZ COORD
        MOVE    D6,(A3)+                        | PUT VERT COORD
        MOVE    D4,(A3)+                        | PUT BOTTOM H COORD
NOCHNG_EXIT:
        MOVE.L  0x2C(SP),A0                     | Load destination buffer to calc index

| ---------------------------------------------------
|
| UPDATE INDEX TO REFLECT POINTS ADDED.
|
        SUB.L   (A0),A3                         | INDEX := BUFPTR-BUFSTART
        MOVE    A3,(A4)                         | UPDATE INDEX
PUTLINE_GOHOME:
        MOVEM.L (SP)+,D3-D7/A2-A4               | GOHOME: RESTORE REGS
        MOVE.L  (SP)+,A0                        | Pop return address before clearing params
        ADDA    #0x14,SP                        | Pop 20 bytes of parameters from stack
        JMP     (A0)                            | Return to caller


