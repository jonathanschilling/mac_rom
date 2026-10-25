| .FUNC RgnOp,7
| .REF SectScan,DiffScan,UnionScan,XorScan,InsetScan,SetSize
| -------------------------------------------------------------------
|
| FUNCTION RgnOp(rgnA,rgnB: RgnHandle;
| bufHandle: Handle;
| maxBytes: INTEGER;
| op,dh: INTEGER;
| okGrow: BOOLEAN): INTEGER;
|
| Computes the intersection, difference, union, or XOR of two regions,
| or the horizontal inset of one region, and stores the result as an
| unpacked array of sorted inversion points in bufHandle. Returns the
| number of points as the function value. BufHandle will be grown only
| if more space is needed needed and okGrow is true.
|
| OP = 0: SectScan
| 2: DIFF A-B
| 4: UNION
| 6: XOR
| 8: HORIZ INSET
|
|
| A6 OFFSETS OF PARAMETERS AND LOCALS AFTER LINK:
|
| Called during boot (7,474 times in 30s trace).
RgnOp:
        LINK    A6,#-0x56                       | allocate stack frame
.set PARAMSIZE, 20                              | TOTAL # BYTES
.set RESULT, PARAMSIZE+8                        | INTEGER, FUNCTION RESULT
.set RGNA, RESULT-4                             | LONG, RGNHANDLE
.set RGNB, RGNA-4                               | LONG, RGNHANDLE
.set BUFHANDLE, RGNB-4                          | LONG, HANDLE TO POINT BUFFER
.set MAXBYTES, BUFHANDLE-2                      | WORD
.set OP, MAXBYTES-2                             | WORD
.set DH, OP-2                                   | WORD
.set OKGROW, DH-2                               | BOOLEAN

.set SCAN1, -4                                  | long
.set SCAN2, SCAN1-4                             | long
.set SCAN3, SCAN2-4                             | long
.set SCAN4, SCAN3-4                             | long
.set SCAN5, SCAN4-4                             | long
.set NEXTA, SCAN5-2                             | WORD
.set NEXTB, NEXTA-2                             | WORD
.set VERT, NEXTB-2                              | WORD
.set BUFPTR, VERT-4                             | LONG, ^POINT
.set BUFLIMIT, BUFPTR-4                         | LONG
.set FAKEB, BUFLIMIT-18                         | 18 BYTE FAKE RGN DATA
.set MASTERB, FAKEB-4                           | LONG
.set FAKEA, MASTERB-18                          | 18 BYTE FAKE RGN DATA
.set MASTERA, FAKEA-4                           | LONG
.set CASEJMP, MASTERA-4                         | LONG
.set SAVESTK, CASEJMP-4                         | LONG
.set VARSIZE, SAVESTK                           | TOTAL BYTES OF LOCALS

        MOVEM.L D3-D7/A2-A4,-(SP)               | SAVE REGS
        MOVE.L  A7,-0x56(A6)                    | REMEMBER STACK PTR

| ------------------------------------------------------------
|
| DE-REFERENCE RGNA AND RGNB AND OFFSET TO FIRST RGNDATA.
| IF EITHER IS RECTANGULAR, REPLACE IT WITH AN EXPANDED ONE.
|
        LEA.L   -0x4E(A6),A2                    | POINT TO FAKE AREA
        LEA.L   0x18(A6),A0                     | POINT TO RGNA HANDLE

| ------------------------------------------------------------
|
        BSR     EXPAND                          | DE-REFERENCE AND EXPAND
        MOVE.L  A0,A3                           | SAVE RGNA DATA PTR IN A3
        LEA.L   0x14(A6),A0                     | POINT TO RGNB HANDLE
        BSR     EXPAND                          | DE-REFERENCE AND EXPAND
        MOVE.L  A0,A4                           | SAVE RGNB DATA PTR IN A4

| -----------------------------------------------------------
|
| SET UP A CASE JUMP BASED ON OP
|
        LEA.L   SectScan(PC),A0                 | get address of SectScan
        MOVE    0xC(A6),D0                      | get op parameter
        BEQ.B   CASEOK                          | BR IF OP = SectScan
        LEA.L   DiffScan(PC),A0                 | get address of DiffScan
        SUBQ.W  #0x2,D0                         | is op = DiffScan (2) ?
        BEQ.B   CASEOK                          | BR IF OP = DIFF
        LEA.L   UnionScan(PC),A0                | get address of UnionScan
        SUBQ.W  #0x2,D0                         | is op = UnionScan (4) ?
        BEQ.B   CASEOK                          | BR IF OP = UNION
        LEA.L   XorScan(PC),A0                  | get address of XorScan
        SUBQ.W  #0x2,D0                         | is op = XorScan (6) ?
        BEQ.B   CASEOK                          | BR IF OP = XOR
        LEA.L   InsetScan(PC),A0                | ELSE OP = INSET
CASEOK:
        MOVE.L  A0,-0x52(A6)                    | SAVE FOR LATER
        MOVE.L  A7,D0                           | get current stack pointer
        SUB.L   (HeapEnd).w,D0                  | subtract HeapEnd to get stack available
        SUBI.L  #0x400,D0                       | subtract 1K for safety margin
        CMPI.L  #0xC8,D0                        | is available stack < 200 bytes?

| -----------------------------------------------------------------
|
| Calc bufSize based on StackAvail and allocate 5 scan buffers
|
| _StackAvail ;get stack avail in D0.L
        BGE.B   STKOK1                          | no, continue
        MOVE    #40,D0                          | yes, make bufSize = 40 bytes
        BRA.B   ALLOC                           | and continue

| ----------------------------------------------------------
|
| STKOK1
|
| Called during boot (7,474 times in 30s trace).
STKOK1:
        DIVS    #5,D0                           | no, divide for 5 buffers
        BVC.B   STKOK2                          | overflow ?
        MOVE    #30000,D0                       | yes, use 30K bytes
STKOK2:
        BCLR    #0,D0                           | make bufSize even
ALLOC:
        SUB     D0,SP                           | allocate one buffer
        MOVE.L  A7,-0x4(A6)                     | remember buffer pointer
        SUB     D0,SP                           | allocate one buffer
        MOVE.L  A7,-0x8(A6)                     | remember buffer pointer
        SUB     D0,SP                           | allocate one buffer
        MOVE.L  A7,-0xC(A6)                     | remember buffer pointer
        SUB     D0,SP                           | allocate one buffer
        MOVE.L  A7,-0x10(A6)                    | remember buffer pointer
        SUB     D0,SP                           | allocate one buffer
        MOVE.L  A7,-0x14(A6)                    | remember buffer pointer

| -----------------------------------------------------------
|
| INIT ASSORTED POINTERS
|
        MOVE.L  0x10(A6),A0                     | GET BUFHANDLE

| -----------------------------------------------------------
|
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        MOVE.L  A0,-0x1E(A6)                    | BUFPTR := BUFSTART
        ANDI    #-0x8,0xE(A6)                   | round maxBytes down to multiple of 8
        ADDA    0xE(A6),A0                      | add to bufStart to get bufLimit
        MOVE.L  A0,-0x22(A6)                    | BUFLIMIT:=BUFSTART+MAXBYTES
        MOVE.L  -0x4(A6),A0                     | get pointer to scan buffer 1 (scanA)
        MOVE.L  A0,D4                           | SCANA := @SCAN1
        MOVE    #32767,D0                       | get end marker
        MOVE    D0,(A0)                         | INIT SCANA TO EMPTY
        MOVE.L  -0x8(A6),A0                     | get pointer to scan buffer 2 (scanB)
        MOVE.L  A0,D5                           | SCANB := @SCAN2
        MOVE    D0,(A0)                         | INIT SCANB TO EMPTY
        MOVE.L  -0xC(A6),A0                     | get pointer to scan buffer 3 (scanC)
        MOVE.L  A0,D6                           | SCANC := @SCAN3
        MOVE    D0,(A0)                         | INIT SCANC TO EMPTY
        MOVE.L  -0x10(A6),A0                    | get pointer to scan buffer 4 (tempScan)
        MOVE.L  A0,D7                           | TEMPSCAN := @SCAN4
        MOVE    (A3)+,-0x16(A6)                 | NEXTA := FIRST VERT IN A
        MOVE    (A4)+,-0x18(A6)                 | NEXTB := FIRST VERT IN B
        CMPI    #0x8,0xC(A6)                    | is op = InsetScan (8)?
        BNE.B   RGNOP_NXTVERT                   | NO, CONTINUE
        MOVE    D0,-0x18(A6)                    | YES, NEXTB := 32767
RGNOP_NXTVERT:
        MOVE    -0x16(A6),D0                    | GET NEXT VERT IN A
        CMP     -0x18(A6),D0                    | WHICH COMES FIRST ?
        BEQ.B   BOTH                            | SAME, UPDATE BOTH RGNS
        BGT.B   UPDATEB                         | B, UPDATE RGNB ONLY
        BSR.B   UPDATEA                         | A, UPDATE RGNA ONLY
        BRA.B   CALC                            | CALC NEW C-SCAN

| ----------------------------------------------------------
|
| UPDATEA
|
| Called during boot (30,111 times in 30s trace).
UPDATEA:
        MOVE    -0x16(A6),-0x1A(A6)             | VERT := NEXTA
        MOVE.L  A3,A0                           | SRCA := PTRA
        MOVE.L  D4,A1                           | SRCB := SCANA
        MOVE.L  D7,A2                           | DSTC := TEMPSCAN
        JSR     XorScan(PC)                     | XORSCAN(PTRA,SCANA,TEMPSCAN)
        MOVE.L  A0,A3                           | BUMP PTRA TO END OF SCAN
        MOVE    (A3)+,-0x16(A6)                 | NEXTA := NEXT VERT
        EXG     D4,D7                           | SWAP SCANA AND TEMPSCAN
        RTS                                     | RETURN TO LOCAL CALLER

| ----------------------------------------------------------
|
| BOTH
|
| Called during boot (11,252 times in 30s trace).
BOTH:
        CMPI    #0x7FFF,D0                      | have we reached the end marker?
        BEQ     RGNOP_DONE                      | YES, WE'RE ALL FINISHED
        BSR.B   UPDATEA                         | UPDATE RGNA
UPDATEB:
        MOVE    -0x18(A6),-0x1A(A6)             | VERT := NEXTB
        MOVE.L  A4,A0                           | SRCA := PTRB
        MOVE.L  D5,A1                           | SRCB := SCANB
        MOVE.L  D7,A2                           | DSTC := TEMPSCAN
        JSR     XorScan(PC)                     | XORSCAN(PTRB,SCANB,TEMPSCAN)
        MOVE.L  A0,A4                           | BUMP PTRB TO END OF SCAN
        MOVE    (A4)+,-0x18(A6)                 | NEXTB := NEXT VERT
        EXG     D7,D5                           | SWAP SCANB AND TEMPSCAN

| ---------------------------------------------------------
|
| CALCULATE SectScan, DIFF, UNION, XOR, OR INSET INTO SCANC
|
| Called during boot (63,457 times in 30s trace).
CALC:
        MOVE.L  D4,A0                           | POINT TO SCANA
        MOVE.L  D5,A1                           | POINT TO SCANB
        MOVE.L  D7,A2                           | POINT TO TEMPSCAN
        MOVE    0xA(A6),D2                      | pass dh parameter in D2
        PEA.L   CHANGES(PC)                     | PUSH RETURN ADDR
        MOVE.L  -0x52(A6),-(SP)                 | PUSH CASE JUMP
        RTS                                     | DO CASE JSR

| -------------------------------------------------------------
|
| FIND ANY CHANGES NOT IN PREVIOUS SCANC, THEN UPDATE SCANC
|
| Called during boot (63,457 times in 30s trace).
CHANGES:
        MOVE.L  D7,A0                           | GET TEMPSCAN
        MOVE.L  D6,A1                           | GET SCANC
        MOVE.L  -0x14(A6),A2                    | GET OUTPUT SCAN
        JSR     XorScan(PC)                     | XorScan(tempScan,scanC,@SCAN5);
        EXG     D7,D6                           | SWAP TEMPSCAN AND SCANC
        MOVE.L  -0x14(A6),A0                    | POINT TO OUTPUT SCAN
        MOVE.L  -0x1E(A6),A1                    | POINT TO DST POINT BUFFER
        MOVE.L  -0x22(A6),A2                    | GET BUFLIMIT
        MOVE.L  -0x1A(A6),D0                    | GET VERT COORD IN HI WORD
        BRA.B   OUTTEST                         | GO TO LOOP START

| ----------------------------------------------------------
|
| CHANGES_NO
|
| Called during boot (88,978 times in 30s trace).
CHANGES_NO:
        MOVE    (A0)+,D0                        | insert horiz coordinate into low word of D0
        MOVE.L  D0,(A1)+                        | PUT LEFT POINT
        MOVE    (A0)+,D0                        | insert horiz coordinate into low word of D0
        MOVE.L  D0,(A1)+                        | PUT RIGHT POINT
OUTTEST:
        CMP.L   A2,A1                           | IS BUFPTR >= BUFLIMIT ?
        BCS.B   OUTTEST_NO                      | branch if buffer not full yet

| -----------------------------------------------------------
|
| THE POINT BUFFER IS FULL, GROW IT IF OKGROW IS TRUE
|
        TST.B   0x8(A6)                         | ARE WE ALLOWED TO GROW ?

| -----------------------------------------------------------
|
        BEQ     RGNOP_ABORT                     | NO, ABORT RGNOP
        MOVE.L  A0,D1                           | YES, SAVE OUTPUT SCAN PTR
        MOVE.L  0x18(A6),A0                     | GET RGNA MASTER
        SUB.L   (A0),A3                         | MAKE RGNA PTR RELATIVE
        MOVE.L  0x14(A6),A0                     | GET RGNB MASTER
        SUB.L   (A0),A4                         | MAKE RGNB PTR RELATIVE
        MOVE.L  0x10(A6),A0                     | GET BUFHANDLE
        SUB.L   (A0),A1                         | MAKE BUFPTR RELATIVE
        SUB.L   (A0),A2                         | MAKE BUFLIMIT RELATIVE, = SIZE
        ADD     #256,A2                         | BUMP BUFLIMIT 256 BYTES
        MOVEM.L D0-D2/A0-A2,-(SP)               | SAVE REGS
        MOVE.L  A0,-(SP)                        | PUSH BUFHANDLE
        MOVE    A2,-(SP)                        | push new size
        JSR     SetHSize(PC)                    | GROW POINT BUFFER
        MOVEM.L (SP)+,D0-D2/A0-A2               | RESTORE REGS
        MOVE.L  0x18(A6),A0                     | GET RGNA MASTER
        ADD.L   (A0),A3                         | MAKE RGNA UN-RELATIVE
        MOVE.L  0x14(A6),A0                     | GET RGNB MASTER
        ADD.L   (A0),A4                         | MAKE RGNB UN-RELATIVE
        MOVE.L  0x10(A6),A0                     | GET BUFHANDLE
        ADD.L   (A0),A1                         | MAKE BUFPTR UN-RELATIVE
        ADD.L   (A0),A2                         | MAKE BUFLIMIT UN-RELATIVE
        MOVE.L  A2,-0x22(A6)                    | UPDATE BUFLIMIT
        MOVE.L  D1,A0                           | RESTORE OUTPUT SCAN PTR
OUTTEST_NO:
        CMPI    #0x7FFF,(A0)                    | reach end of scan?
        BNE.B   CHANGES_NO                      | NO, GO FOR MORE
        MOVE.L  A1,-0x1E(A6)                    | UPDATE BUFPTR
        BRA     RGNOP_NXTVERT                   | LOOP FOR NEXT VERT

| ----------------------------------------------------------
|
| EXPAND
|
| Called during boot (14,948 times in 30s trace).
EXPAND:
        MOVE.L  (A0),A1                         | GET RGNHANDLE
        MOVE.L  (A1),A1                         | DE-REFERENCE HANDLE
        CMPI    #0xA,(A1)                       | is region size 10 bytes (rectangular)?
        BNE.B   RGNOP_NOTRECT                   | NO, DON'T EXPAND IT
        MOVE.L  A2,(A0)                         | POINT HANDLE TO FAKE MASTER
        LEA.L   -0x6(A2),A0                     | offset fake pointer so fakeData is at +10
        MOVE.L  A0,(A2)+                        | FILL IN FAKE MASTER
        MOVE.L  0x2(A1),(A2)+                   | put top and left coordinates
        MOVE    0x8(A1),(A2)+                   | put right coordinate
        MOVE    #32767,D0                       | get end marker
        MOVE    D0,(A2)+                        | PUT HORIZ TERMINATOR
        MOVE    0x6(A1),(A2)+                   | put bottom coordinate
        MOVE    0x4(A1),(A2)+                   | put left coordinate
        MOVE    0x8(A1),(A2)+                   | put right coordinate
        MOVE    D0,(A2)+                        | PUT HORIZ TERMINATOR
        MOVE    D0,(A2)+                        | PUT VERT TERMINATOR
        MOVE.L  A0,A1                           | PUT FAKE RGNPTR IN A1
RGNOP_NOTRECT:
        LEA.L   RGNDATA(A1),A0                  | OFFSET TO FIRST REGION DATA
        RTS                                     | AND RETURN

| ----------------------------------------------------------
|
| RGNOP_ABORT
|
| Called during boot.
RGNOP_ABORT:
        MOVE.L  A1,-0x1E(A6)                    | UPDATE BUFPTR
RGNOP_DONE:
        MOVE.L  -0x1E(A6),D0                    | GET BUFPTR
        MOVE.L  0x10(A6),A0                     | GET BUFHANDLE

| RTS ;AND RETURN
        SUB.L   (A0),D0                         | BYTES USED = BUFPTR - BUFSTART
        LSR     #2,D0                           | DIV BY 4 FOR NPOINTS
        MOVE    D0,0x1C(A6)                     | RETURN NPOINTS
        MOVE.L  -0x56(A6),SP                    | STRIP SCAN BUFFERS
        MOVEM.L (SP)+,D3-D7/A2-A4               | RESTORE REGS
        UNLK    A6                              | unlink stack frame
        MOVE.L  (SP)+,A0                        | get return address
        ADDA    #0x14,SP                        | pop 20 bytes of parameters
        JMP     (A0)                            | return to caller

| .PROC SectScan,3
| .DEF DiffScan,UnionScan
| ---------------------------------------------------------
|
| PROCEDURE SectScan(srcA,srcB,dstC: ScanPtr);
|
| Calculate the intersection, difference, or union of two inversion scans.
|
| Each input scan is a sorted array of integers terminated by 32767.
| The output scan contains the inversion coordinates for the result.
|
| INPUTS: A0 SRCA
| A1 SRCB
| A2 DSTC
|
| CLOBBERS D0-D3, A0-A2
|
| Called during boot (26,410 times in 30s trace).
SectScan:
        CLR     D2                              | RESET ASTATE OFF
        CLR     D3                              | RESET BSTATE OFF
        BRA.B   SECTSCAN_SHARE                  | SHARE CODE

| ----------------------------------------------------------
|
| Diff Scan
|
| Called during boot (36,951 times in 30s trace).
DiffScan:
        CLR     D2                              | RESET ASTATE OFF
        BRA.B   UNION2                          | SHARE CODE

| ----------------------------------------------------------
|
| Union Scan
|
| Called during boot.
UnionScan:
        MOVEQ   #-1,D2                          | SET ASTATE ON
UNION2:
        MOVEQ   #-1,D3                          | SET BSTATE ON
SECTSCAN_SHARE:
        MOVE    (A0)+,D0                        | SHARE: GET NEXTA
        MOVE    (A1)+,D1                        | GET NEXTB
NEXT:
        CMP     D1,D0                           | IS NEXTA < NEXT B ?
        BLT.B   ALESS                           | YES, BRANCH
        BGT.B   BLESS                           | BR IF NEXTB IS LESS
        CMPI    #0x7FFF,D0                      | are both at end marker?
        BEQ.B   SKIP2_EXIT                      | YES, QUIT
        CMP     D3,D2                           | ARE ASTATE AND BSTATE SAME ?
        BNE.B   SKIP0                           | NO, SKIP
        MOVE    D0,(A2)+                        | YES, PUT CHANGE
SKIP0:
        MOVE    (A0)+,D0                        | GET NEW NEXTA
        NOT     D2                              | TOGGLE ASTATE
        MOVE    (A1)+,D1                        | GET NEW NEXTB
        NOT     D3                              | TOGGLE BSTATE
        BRA.B   NEXT                            | LOOP FOR MORE

| ----------------------------------------------------------
|
| ALESS
|
| Called during boot (104,814 times in 30s trace).
ALESS:
        TST     D3                              | TEST BSTATE
        BEQ.B   SKIP1                           | SKIP IF NOT TRUE
        MOVE    D0,(A2)+                        | PUT NEXTA
SKIP1:
        MOVE    (A0)+,D0                        | GET NEW NEXTA
        NOT     D2                              | AND TOGGLE ASTATE
        BRA.B   NEXT                            | LOOP FOR MORE

| ----------------------------------------------------------
|
| BLESS
|
| Called during boot (51,958 times in 30s trace).
BLESS:
        TST     D2                              | TEST ASTATE
        BEQ.B   SKIP2                           | SKIP IF NOT TRUE
        MOVE    D1,(A2)+                        | PUT NEXTB
SKIP2:
        MOVE    (A1)+,D1                        | GET NEW NEXTB
        NOT     D3                              | AND TOGGLE BSTATE
        BRA.B   NEXT                            | LOOP FOR MORE

| ----------------------------------------------------------
|
| SKIP2_EXIT
|
| Called during boot (63,457 times in 30s trace).
SKIP2_EXIT:
        MOVE    #32767,(A2)+                    | DONE: PUT END MARKER INTO DST
        RTS                                     | return from SKIP2_EXIT

| ------------------------------------------------------------------------
|
| LOCAL ROUTINE TO EXPAND A RECTANGULAR REGION TO ITS INVERSION POINTS.
| ENTER WITH ADDR OF RGNHANDLE IN A0, ADDR OF FAKE MASTER IN A2.
| RETURNS IN A0 DE-REFERENCED POINTER BUMPED TO FIRST RGNDATA,
| AND A2 BUMPED TO NEXT AVAILABLE FAKE MASTER.
|
| .PROC InsetScan,3
| .DEF XorScan
| ---------------------------------------------------------
|
| PROCEDURE InsetScan(src,dst: ScanPtr; dh: INTEGER);
|
| Horizontally inset an inversion scan by dh;
|
| The input scan is a sorted array of integers terminated by 32767.
| The output scan contains the inversion coordinates for the inset.
|
| INPUTS: A0 SRC
| A2 DST
| D2 DH
|
| CLOBBERS D0-D1/A0-A2
InsetScan:
        TST     D2                              | IS DH NEG ?
        BLT.B   OUTSET                          | YES, OUTSET
INSET:
        CMPI    #0x7FFF,(A0)                    | reached end of scan?

| ---------------------------------------------------------------
|
| GET EACH PAIR OF COORDS, INSET THEM, AND CANCEL IF THEY CROSS.
|
        BEQ.B   OUTOK2_EXIT                     | QUIT WHEN FOUND
        MOVE    (A0)+,D0                        | GET LEFT COORD
        MOVE    (A0)+,D1                        | GET RIGHT COORD
        ADD     D2,D0                           | inset left coordinate
        SUB     D2,D1                           | inset right coordinate
        CMP     D1,D0                           | IS LEFT >= RIGHT ?
        BGE.B   INSET                           | YES, SKIP BOTH
        MOVE    D0,(A2)+                        | PUT LEFT COORD TO DST
        MOVE    D1,(A2)+                        | PUT RIGHT COORD TO DST
        BRA.B   INSET                           | LOOP ENTIRE SCAN

| ------------------------------------------------------------------
|
| GET EACH PAIR OF COORDS, OUTSET THEM, AND CANCEL IF THEY CROSS.
|
OUTSET:
        MOVE    #-32767,A1                      | OLDRIGHT := -32767

| ------------------------------------------------------------------
|
| GET EACH PAIR OF COORDS, OUTSET THEM, AND CANCEL IF THEY CROSS.
|
        BRA.B   OUTOK2_LOOP                     | GO TO LOOP START

| ----------------------------------------------------------
|
| OUTLOOP
|
OUTLOOP:
        MOVE    (A0)+,D0                        | GET LEFT COORD
        MOVE    (A0)+,D1                        | GET RIGHT COORD
        ADD     D2,D0                           | ADD DH TO LEFT
        SUB     D2,D1                           | SUB DH FROM RIGHT
        CMP     A1,D0                           | IS LEFT <= OLDRIGHT ?
        BGT.B   OUTOK                           | NO, CONTINUE
        SUBQ.W  #0x2,A2                         | regions overlap, merge by dropping previous right coord
        BRA.B   OUTOK2                          | AND CONTINUE

| ----------------------------------------------------------
|
| OUTOK
|
OUTOK:
        MOVE    D0,(A2)+                        | PUT LEFT COORD
OUTOK2:
        MOVE    D1,(A2)+                        | PUT RIGHT COORD
        MOVE    D1,A1                           | OLDRIGHT := RIGHT
OUTOK2_LOOP:
        CMPI    #0x7FFF,(A0)                    | reached end of scan?
        BNE.B   OUTLOOP                         | AND LOOP ENTIRE SCAN
OUTOK2_EXIT:
        MOVE    #32767,(A2)+                    | DONE: PUT TERMINATOR
        RTS                                     | return from OUTOK2_EXIT

| ----------------------------------------------------------
|
| EQUAL
|
| Called during boot (264,977 times in 30s trace).
EQUAL:
        CMPI    #0x7FFF,D0                      | are both at end marker?

| RTS

| --------------------------------------------------------------
|
| LOCAL PROCEDURE XorScan(srcA,srcB,dstC: ScanPtr);
|
| Form the exclusive-or of two inversion scans.
|
| Each input scan is a sorted array of integers terminated by 32767.
| The output scan conatins all input coordinates from each, but
| with duplicate pairs cancelled. It also is terminated by 32767.
|
| INPUTS: A0 SRCA
| A1 SRCB
| A2 DSTC
|
| CLOBBERS D0-D1, A0-A2
        BEQ.B   OUTOK2_EXIT                     | YES, QUIT
| XorScan -- xORSCAN(PTRA,SCANA,TEMPSCAN).
XorScan:
        MOVE    (A0)+,D0                        | GET NEXT A
        MOVE    (A1)+,D1                        | GET NEXT B
INSETSCAN_NEXT:
        CMP     D1,D0                           | NEXT: WHICH IS LESS, A OR B ?
        BEQ.B   EQUAL                           | THE SAME, SO CANCEL
        BLT.B   INSETSCAN_ALESS                 | A IS LESS
        MOVE    D1,(A2)+                        | BLESS: PUT B TO DST
        MOVE    (A1)+,D1                        | GET NEXT B
        BRA.B   INSETSCAN_NEXT                  | LOOP FOR MORE

| ----------------------------------------------------------
|
| INSETSCAN_ALESS
|
| Called during boot (186,218 times in 30s trace).
INSETSCAN_ALESS:
        MOVE    D0,(A2)+                        | ALESS: PUT A TO DST
        MOVE    (A0)+,D0                        | GET NEXT A
        BRA.B   INSETSCAN_NEXT                  | LOOP FOR MORE


