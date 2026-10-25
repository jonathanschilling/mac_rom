| -----------------------------------------------------------
|
| --> PUTLINE.TEXT
|
| Decompose a line segment into a list of inversion points.

| .PROC PUTLINE,5
| .REF SETSIZE
| ------------------------------------------------------------------
|
| PROCEDURE PutLine(pt1,pt2: Point; dst: Handle; VAR index,bufMax: INTEGER);
|
| INVERSION POINTS FOR A LINE SEGMENT
|
| SP OFFSETS OF PARAMETERS (after MOVEM.L pushes 8 longs = 32 bytes):
|   PT1 +0x34, PT2 +0x30, BUF +0x2C, INDEX +0x28, BUFMAX +0x24.
|
PUTLINE:
    MOVEM.L     D3-D7/A2-A4,-(A7)               | SAVE REGS, 8*4 ==> 32
    MOVE.W      0x36(A7),D2                     | Load pt1.h to check for vertical line
    MOVE.W      0x32(A7),D4                     | Load pt2.h to check for vertical line
| -----------------------------------------------------
|
| IF LINE IS VERTICAL, IGNORE IT.
|
    CMP.W       D2,D4                           | IS THIS A VERTICAL LINE ?
    BEQ.W       PUTLINE_GOHOME                  | YES, IGNORE IT
| ------------------------------------------------------
|
| CALC BYTESNEEDED = 8 * ( Min(ABS(dh),ABS(dv)) + 1)
|
    MOVE.W      D2,D0                           | GET H1
    SUB.W       D4,D0                           | SUBTRACT H2
    BPL.B       DHPOS                           | BR IF DH POS
    NEG.W       D0                              | ELSE TAKE ABSOLUTE VALUE
DHPOS:
    MOVE.W      0x34(A7),D1                     | Load pt1.v coordinate to calculate dv
    SUB.W       0x30(A7),D1                     | Subtract pt2.v from pt1.v to find dv
    BPL.B       DVPOS                           | BR IF DV POS
    NEG.W       D1                              | ELSE TAKE ABSOLUTE VALUE
DVPOS:
    CMP.W       D1,D0                           | IS DH <= DV ?
    BLE.B       DVPOS_OK                        | YES, CONTINUE
    MOVE.W      D1,D0                           | NO, PUT MIN(DH,DV) INTO D0
DVPOS_OK:
    ADDQ.W      #0x1,D0                         | Add 1 to min(dh,dv) to include endpoints
    LSL.W       #0x3,D0                         | TIMES EIGHT FOR BYTESNEEDED
    MOVEA.L     0x2C(A7),A3                     | Load destination point buffer handle
    MOVEA.L     0x28(A7),A4                     | Load pointer to buffer index variable
| -----------------------------------------------------
|
| GROW POINT BUFFER AS NECESSARY TO HOLD BYTESNEEDED
|
    ADD.W       (A4),D0                         | NEWSIZE := INDEX + BYTESNEEDED
    MOVEA.L     0x24(A7),A0                     | Load pointer to bufMax to check limits
    CMP.W       (A0),D0                         | DO WE HAVE TO GROW DSTBUF ?
    BLE.B       DVPOS_NO                        | NO, CONTINUE
    ADDI.W      #0x200,D0                       | Expand buffer size by 512 bytes chunks
    MOVE.W      D0,(A0)                         | UPDATE NEW BUFMAX
    MOVE.L      A3,-(A7)                        | PUSH DSTBUF HANDLE
    MOVE.W      D0,-(A7)                        | PUSH NEW BUFMAX
    JSR         SETHSIZE(PC)                    | MAKE THE BUFFER BIGGER
    MOVE.W      0x36(A7),D2                     | Restore pt1.h clobbered by SetHSize
| NOGROW
DVPOS_NO:
    MOVEA.L     (A3),A3                         | DE-REFERENCE DSTHANDLE
    ADDA.W      (A4),A3                         | ADD INDEX TO BUFPTR
    MOVE.W      0x34(A7),D1                     | Load pt1.v for horizontal line check
    MOVE.W      0x30(A7),D3                     | Load pt2.v for horizontal line check
| -----------------------------------------------------
|
| IF LINE IS HORIZONTAL, PUT ITS TWO ENDPOINTS
|
    CMP.W       D1,D3                           | IS THIS A HORIZONTAL LINE ?
    BNE.B       PUTLINE_SLANTED                 | NO, BRANCH
    MOVE.W      D1,(A3)+                        | PUT V1 VERT COORD
    MOVE.W      D2,(A3)+                        | PUT H1 HORIZ COORD
    MOVE.W      D3,(A3)+                        | PUT V2 VERT COORD
    MOVE.W      D4,(A3)+                        | PUT H2 HORIZ COORD
    BRA.B       NOCHNG_EXIT                     | UPDATE INDEX AND QUIT
| ------------------------------------------------------
|
| LINE IS SLANTED. DIVIDE IT INTO HORIZONTAL SLABS
| AND PUT THE TWO ENDPOINTS OF EACH SLAB.
|
| START BY SORTING POINTS VERTICALLY.
|
PUTLINE_SLANTED:
    BGT.B       NOSWAP                          | SKIP IF ALREADY IN ORDER
    EXG         D1,D3                           | SORT POINTS BY VERTICAL
    EXG         D2,D4                           | SWAP HORIZ TO MATCH
NOSWAP:
    MOVE.W      D1,D6                           | INIT V TO TOPV
| ------------------------------------------------------------
|
| CALCULATE FIXED POINT SLOPE = FixRatio(dh,dv);
|
    CLR.L       -(A7)                           | MAKE ROOM FOR FCN RESULT
    MOVE.W      D4,-(A7)                        | PUSH BOTTOM HORIZ
    SUB.W       D2,(A7)                         | CALC DH
    MOVE.W      D3,-(A7)                        | PUSH BOTTOM VERT
    SUB.W       D1,(A7)                         | CALC DV
    _FixRatio                                   | CALC FIXED POINT SLOPE
    MOVE.L      (A7)+,D7                        | POP RESULT
    MOVE.W      D2,D1                           | Copy starting top horizontal position
| ---------------------------------------------------------
|
| SET UP STARTING HORIZ FIXED POINT.
|
    SWAP.W      D1                              | HORIZ.INT := TOP HORIZ
    MOVE.W      #0x8000,D1                      | Initialize fixed-point fraction to 0.5
|
| ADJUST HORIZ DEPENDING ON SIGN AND MAGNITUDE OF SLOPE
|
    MOVE.L      D7,D0                           | COPY SLOPE
    ASR.L       #0x1,D0                         | CALC SLOPE/2
    ADD.L       D0,D1                           | HORIZ := HORIZ + SLOPE/2
    MOVE.L      #0x10000,D0                     | Load fixed-point value of 1.0 for bounds
    TST.L       D7                              | IS SLOPE NEG ?
    BMI.B       NOSWAP_OK                       | YES, CONTINUE
    CMP.L       D0,D7                           | IS SLOPE < ONE ?
    BGE.B       NOSWAP_NO                       | NO, CONTINUE
    ADD.L       D7,D1                           | ADD SLOPE TO LEFTEDGE
    BRA.B       NOSWAP_NO                       | CONTINUE
| ----------------------------------------------------------
|
| NOSWAP_OK
|
NOSWAP_OK:
    CMPI.L      #0xFFFF0000,D7                  | Is fixed-point slope >= -1.0?
    BGE.B       NOSWAP_NO                       | YES, CONTINUE
    ADD.L       D0,D1                           | YES, HORIZ := HORIZ + 1
| SLOPEOK
| ------------------------------------------------------
|
| FOR VERT:=TOPV TO BOTV-1 ADD SLOPE TO HORIZ AND PUT SLABS
|
NOSWAP_NO:
    MOVE.W      D2,D5                           | H:=TOPH
LOOP:
    SWAP.W      D1                              | GET HORIZ.INT INTO D1 LOWER
    CMP.W       D1,D5                           | HAS HORIZ.INT CHANGED ?
    BEQ.B       NOCHNG                          | NO, CONTINUE
    MOVE.W      D6,(A3)+                        | YES, PUT VERT COORD
    MOVE.W      D5,(A3)+                        | PUT OLD HORIZ COORD
    MOVE.W      D1,D5                           | Save current horizontal integer part
    MOVE.W      D6,(A3)+                        | PUT VERT COORD
    MOVE.W      D5,(A3)+                        | PUT NEW HORIZ COORD
NOCHNG:
    SWAP.W      D1                              | PUTBACK HORIZ.INT INTO D1 UPPER
    ADDQ.W      #0x1,D6                         | Advance vertical coordinate to next slab
    ADD.L       D7,D1                           | ADD SLOPE TO HORIZ
    CMP.W       D6,D3                           | IS VERT AT BOTTOM VERT YET ?
    BNE.B       LOOP                            | NO, GO FOR MORE
| -------------------------------------------------
|
| FINISH UP LAST SLAB
|
    CMP.W       D4,D5                           | IS OLDH = BOTTOM H ?
    BEQ.B       NOCHNG_EXIT                     | YES, CONTINUE
    MOVE.W      D6,(A3)+                        | NO, PUT VERT COORD
    MOVE.W      D5,(A3)+                        | PUT OLD HORIZ COORD
    MOVE.W      D6,(A3)+                        | PUT VERT COORD
    MOVE.W      D4,(A3)+                        | PUT NEW HORIZ COORD
NOCHNG_EXIT:
    MOVEA.L     0x2C(A7),A0                     | Load destination buffer to calc index
| ---------------------------------------------------
|
| UPDATE INDEX TO REFLECT POINTS ADDED.
|
    SUBA.L      (A0),A3                         | INDEX := BUFPTR-BUFSTART
    MOVE.W      A3,(A4)                         | UPDATE INDEX
PUTLINE_GOHOME:
    MOVEM.L     (A7)+,D3-D7/A2-A4               | GOHOME: RESTORE REGS
    MOVEA.L     (A7)+,A0                        | Pop return address before clearing params
    ADDA.W      #0x14,A7                        | Pop 20 bytes of parameters from stack
    JMP         (A0)                            | Return to caller
