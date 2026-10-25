| --> RGNOP.TEXT
|
| RgnOp, SectScan, InsetScan: the region set operations behind
| SectRgn, UnionRgn, DiffRgn, XOrRgn and InsetRgn.
| Apple source: RgnOp.a (1983 QuickDraw sources).

RgnOp:
        LINK.W   FP,#-562                       | link frame, 562 bytes locals
        MOVEM.L  D3-D7/A2-A4,-(SP)              | save D3-D7,A2-A4
        LEA.L     -0x22E(A6),A2                 | A2 := scan working area
        LEA.L     24(A6),A0                     | A0 := arg slot for rgnA handle
        BSR.W   EXPAND                          | expand rgnA scanlines into buf
        MOVE.L  A0,A3                           | A3 := PTRA (rgnA scan ptr)
        LEA.L     20(A6),A0                     | A0 := arg slot for rgnB handle
        BSR.W   EXPAND                          | expand rgnB scanlines into buf
        MOVE.L  A0,A4                           | POINT TO SCANA
        LEA     SectScan(PC),A0                 | default op proc = SectScan
        MOVE    12(A6),D0                       | POINT TO TEMPSCAN
        BEQ.B   CASEOK                          | op==0 (Sect), use SectScan
        LEA     DiffScan(PC),A0                 | op proc = DiffScan
        SUBQ.W  #0x2,D0                         | op -= 2 (test op==2)
        BEQ.B   CASEOK                          | op==2 (Diff), use DiffScan
        LEA     UnionScan(PC),A0                | op proc = UnionScan
        SUBQ.W  #0x2,D0                         | op -= 2 (test op==4)
        BEQ.B   CASEOK                          | op==4 (Union), use UnionScan
        LEA     XORSCAN_TRAMP(PC),A0            | op proc = XorScan
        SUBQ.W  #0x2,D0                         | op -= 2 (test op==6)
        BEQ.B   CASEOK                          | op==6 (Xor), use XorScan
        LEA     InsetScan(PC),A0                | op == 8 (Inset), use InsetScan
CASEOK:
        MOVE.L  A0,-0x232(A6)                   | POINT TO DST POINT BUFFER
        MOVE.L  16(A6),A0                       | GET BUFLIMIT
        MOVE.L  (A0),A0                         | GET VERT COORD IN HI WORD
        MOVE.L  A0,-0x1FE(A6)                   | save BUFLIMIT (rgnA buffer top)
        ANDI    #-0x8,14(A6)                    | 14(A6) &= -0x8
        ADDA.W  14(A6),A0                       | A0 += rounded maxBytes
        MOVE.L  A0,-0x202(A6)                   | insert horiz coordinate into low word of D0
        LEA.L     -0x64(A6),A0                  | A0 := SCANA addr
        MOVE.L  A0,D4                           | D4 := SCANA ptr
        MOVE    #0x7FFF,(A0)                    | SCANA[0] := 32767 (sentinel)
        LEA.L     -0xC8(A6),A0                  | A0 := SCANB addr
        MOVE.L  A0,D5                           | D5 := SCANB ptr
        MOVE    #0x7FFF,(A0)                    | SCANB[0] := 32767 (sentinel)
        LEA.L     -0x12C(A6),A0                 | A0 := SCANC addr (output)
        MOVE.L  A0,D6                           | D6 := SCANC ptr
        MOVE    #0x7FFF,(A0)                    | SCANC[0] := 32767 (sentinel)
        LEA.L     -0x190(A6),A0                 | A0 := TEMPSCAN addr
        MOVE.L  A0,D7                           | D7 := TEMPSCAN ptr
        MOVE    (A3)+,-0x1F6(A6)                | NEXTA := next vert from PTRA
        MOVE    (A4)+,-0x1F8(A6)                | NEXTB := next vert from PTRB
        CMPI    #0x8,12(A6)                     | is op == INSET (8)?
        BNE.B   RGNOP_NXTVERT                   | no, continue normally
        MOVE    #0x7FFF,-0x1F8(A6)              | INSET op: NEXTB := 32767 (ignore B)
RGNOP_NXTVERT:
        MOVE    -0x1F6(A6),D0                   | get NEXTA
        CMP     -0x1F8(A6),D0                   | compare to NEXTB
        BEQ.B   BOTH                            | same vert: update both
        BGT.B   UPDATEB                         | MORE THAN 4, NOT RECTANGULAR
        BSR.W   UPDATEA                         | NEXTA earlier: update A only
        BRA.B   CALC                            | INSTALL RGNSIZE AND BBOX AND QUIT
BOTH:
        CMPI    #0x7FFF,D0                      | both at 32767 sentinel?
        BEQ.W   RGNOP_DONE                      | yes, regions exhausted
        BSR.W   UPDATEA                         | update A scan
UPDATEB:
        BSR.W   UPDATEA_CONT                    | update B scan

| ---------------------------------------------------------
| CALCULATE SectScan, DIFF, UNION, XOR, OR INSET INTO SCANC
| Called during boot (63,457 times in 30s trace).
CALC:
        MOVE.L  D4,A0                           | A0 := SCANA ptr
        MOVE.L  D5,A1                           | A1 := SCANB ptr
        MOVE.L  D7,A2                           | A2 := TEMPSCAN ptr (output)
        MOVE    10(A6),D2                       | D2 := dh
        PEA.L   CALC_CONT(PC)                   | push CALC_CONT as return addr
        MOVE.L  -0x232(A6),-(SP)                | push selected op proc
        RTS                                     | dispatch to op proc (returns to CALC_CONT)
CALC_CONT:
        MOVE.L  D7,A0                           | A0 := TEMPSCAN ptr
        MOVE.L  D6,A1                           | A1 := SCANC (final output)
        LEA.L     -0x1F4(A6),A2                 | A2 := working buffer
        JSR     XORSCAN_TRAMP(PC)               | merge TEMPSCAN into SCANC via XOR
        EXG     D7,D6                           | swap TEMPSCAN/SCANC ptrs
        LEA.L     -0x1F4(A6),A0                 | A0 := merged scanline buffer
        MOVE.L  -0x1FE(A6),A1                   | A1 := dst PTR for region pack
        MOVE.L  -0x202(A6),A2                   | A2 := dst limit (BUFLIMIT)
        MOVE.L  -0x1FA(A6),D0                   | D0 := current vert
        BRA.B   CALC_CONT_3                     | LOOP FOR MORE
CALC_CONT_2:
        MOVE    (A0)+,D0                        | get next horiz from merged scan
        MOVE.L  D0,(A1)+                        | emit (vert,horiz) to dst pt
        MOVE    (A0)+,D0                        | GET FIRST VERT COORD
        MOVE.L  D0,(A1)+                        | emit (vert,horiz) to dst pt
CALC_CONT_3:
        CMPA.L  A2,A1                           | dst ptr past limit?
        BCS.W   OUTTEST_NO                      | no, continue copying
        TST.B   8(A6)                           | is okGrow flag set?
        BEQ.W   RGNOP_SAVE                      | YES, CONTINUE
        MOVE.L  A0,D1                           | save A0 across SetHSize
        MOVE.L  24(A6),A0                       | A0 := PTRA save slot
        SUBA.L  (A0),A3                         | A3 := offset (PTRA - bufStart)
        MOVE.L  20(A6),A0                       | A0 := PTRB save slot
        SUBA.L  (A0),A4                         | A4 := offset (PTRB - bufStart)
        MOVE.L  16(A6),A0                       | VERT := NEXTA
        SUBA.L  (A0),A1                         | A1 := offset (dst ptr - bufStart)
        SUBA.L  (A0),A2                         | A2 := offset (limit - bufStart)
        ADDA.W  #0x100,A2                       | grow buffer by 256 bytes
        MOVEM.L D0-A2,-(SP)                     | save D0-A2 across SetHSize
        MOVE.L  A0,-(SP)                        | BUMP PTRA TO END OF SCAN
        MOVE    A2,-(SP)                        | NEXTA := NEXT VERT
        JSR     SetHSize(PC)                    | grow ptBuf to new size
        MOVEM.L (SP)+,D0-A2                     | restore D0-A2
        MOVE.L  24(A6),A0                       | A0 := PTRA save slot
        ADDA.L  (A0),A3                         | A3 := PTRA + new bufStart
        MOVE.L  20(A6),A0                       | SRCA := PTRA
        ADDA.L  (A0),A4                         | A4 := PTRB + new bufStart
        MOVE.L  16(A6),A0                       | DSTC := TEMPSCAN
        ADDA.L  (A0),A1                         | A1 := dst ptr + new bufStart
        ADDA.L  (A0),A2                         | A2 := new buffer limit
        MOVE.L  A2,-0x202(A6)                   | NEXTA := NEXT VERT
        MOVEA.L  D1,A0                          | restore A0 from D1
OUTTEST_NO:
        CMPI    #0x7FFF,(A0)                    | is current entry sentinel (32767)?
        BNE.B   CALC_CONT_2                     | NO, CONTINUE
        MOVE.L  A1,-0x1FE(A6)                   | save dst ptr (BUFLIMIT)
        BRA.W   RGNOP_NXTVERT                   | UPDATE INDEX AND QUIT
| ----------------------------------------------------------
| UPDATEA
| Called during boot (30,111 times in 30s trace).
UPDATEA:
        MOVE    -0x1F6(A6),-0x1FA(A6)           | VERT := NEXTA
        MOVE.L  A3,A0                           | SRCA := PTRA
        MOVE.L  D4,A1                           | GET NEXT A
        MOVE.L  D7,A2                           | GET NEXT B
        JSR     XORSCAN_TRAMP(PC)               | XORSCAN(PTRA,SCANA,TEMPSCAN)
        MOVE.L  A0,A3                           | BUMP PTRA TO END OF SCAN
        MOVE    (A3)+,-0x1F6(A6)                | NEXTA := NEXT VERT
        EXG     D4,D7                           | SWAP SCANA AND TEMPSCAN
        RTS                                     | RETURN TO LOCAL CALLER
UPDATEA_CONT:
        MOVE    -0x1F8(A6),-0x1FA(A6)           | GET NEXT B
        MOVE.L  A4,A0                           | SRCA := PTRB
        MOVE.L  D5,A1                           | ALESS: PUT A TO DST
        MOVE.L  D7,A2                           | GET NEXT A
        JSR     XORSCAN_TRAMP(PC)               | XORSCAN(PTRB,SCANB,TEMPSCAN)
        MOVE.L  A0,A4                           | BUMP PTRB TO END OF SCAN
        MOVE    (A4)+,-0x1F8(A6)                | NEXTB := NEXT VERT
        EXG     D7,D5                           | SWAP SCANB AND TEMPSCAN
        RTS                                     | RETURN TO LOCAL CALLER
EXPAND:
        MOVE.L  (A0),A1                         | GET RGNHANDLE
        MOVE.L  (A1),A1                         | DE-REFERENCE HANDLE
        CMPI    #0xA,(A1)                       | IS REGION RECTANGULAR ?
        BNE.B   EXPAND_DONE                     | NO, DON'T EXPAND IT
        MOVE.L  A2,(A0)                         | POINT HANDLE TO FAKE MASTER
        LEA.L     -6(A2),A0                     | POINT 10 BYTES BEFORE DATA
        MOVE.L  A0,(A2)+                        | FILL IN FAKE MASTER
        MOVE.L  2(A1),(A2)+                     | PUT TOP V AND LEFT H
        MOVE    8(A1),(A2)+                     | PUT RIGHT HORIZ
        MOVE    #0x7FFF,(A2)+                   | PUT HORIZ TERMINATOR
        MOVE    6(A1),(A2)+                     | PUT BOTTOM VERT
        MOVE    4(A1),(A2)+                     | PUT LEFT HORIZ
        MOVE    8(A1),(A2)+                     | PUT RIGHT HORIZ
        MOVE    #0x7FFF,(A2)+                   | PUT HORIZ TERMINATOR
        MOVE    #0x7FFF,(A2)+                   | PUT VERT TERMINATOR
        MOVE.L  A0,A1                           | PUT FAKE RGNPTR IN A1
EXPAND_DONE:
        LEA.L     10(A1),A0                     | OFFSET TO FIRST REGION DATA
        RTS                                     | AND RETURN
RGNOP_SAVE:
        MOVE.L  A1,-0x1FE(A6)                   | ABORT: UPDATE BUFPTR
RGNOP_DONE:
        MOVE.L  -0x1FE(A6),D0                   | GET BUFPTR
        MOVE.L  16(A6),A0                       | SHARE: GET NEXTA
        SUB.L   (A0),D0                         | BYTES USED = BUFPTR - BUFSTART
        LSR     #0x2,D0                         | DIV BY 4 FOR NPOINTS
        MOVE    D0,28(A6)                       | RETURN NPOINTS in RESULT
        MOVEM.L (SP)+,D3-D7/A2-A4               | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return PC
        ADDA.W  #0x14,SP                        | strip PARAMSIZE bytes
        JMP     (A0)                            | RTS
XORSCAN_TRAMP:
        BRA.B   XorScan                         | trampoline to XorScan
EQUAL:
        CMPI    #0x7FFF,D0                      | ALL DONE ?
        BEQ.B   OUTOK2_EXIT                     | YES, QUIT
XorScan:
        MOVE    (A0)+,D0                        | GET NEW NEXTB
        MOVE    (A1)+,D1                        | GET NEXT B
INSETSCAN_NEXT:
        CMP     D1,D0                           | WHICH IS LESS, A OR B ?
        BEQ.B   EQUAL                           | SKIP IF NOT TRUE
        BLT.B   INSETSCAN_ALESS                 | A IS LESS
        MOVE    D1,(A2)+                        | BLESS: PUT B TO DST
        MOVE    (A1)+,D1                        | GET NEW NEXTA
        BRA.B   INSETSCAN_NEXT                  | LOOP FOR MORE
INSETSCAN_ALESS:
        MOVE    D0,(A2)+                        | ALESS: PUT A TO DST
        MOVE    (A0)+,D0                        | GET NEXT A
        BRA.B   INSETSCAN_NEXT                  | LOOP FOR MORE
OUTOK2_EXIT:
        MOVE    #0x7FFF,(A2)+                   | PUT NEXTB
        RTS                                     | return from XorScan/InsetScan

| .PROC SectScan,3
| .DEF DiffScan,UnionScan
| ---------------------------------------------------------
| PROCEDURE SectScan(srcA,srcB,dstC: ScanPtr);
| Calculate the intersection, difference, or union of two inversion scans.
| Each input scan is a sorted array of integers terminated by 32767.
| The output scan contains the inversion coordinates for the result.
| INPUTS: A0 SRCA
| A1 SRCB
| A2 DSTC
| CLOBBERS D0-D3, A0-A2
| Called during boot (26,410 times in 30s trace).
SectScan:
        CLR     D2                              | RESET ASTATE OFF
        CLR     D3                              | RESET BSTATE OFF
        BRA.B   SECTSCAN_SHARE                  | SHARE CODE
DiffScan:
        CLR     D2                              | RESET ASTATE OFF
        BRA.B   UNION2                          | SHARE CODE
UnionScan:
        MOVEQ.L #-0x1,D2                        | SET ASTATE ON
UNION2:
        MOVEQ.L #-0x1,D3                        | SET BSTATE ON
SECTSCAN_SHARE:
        MOVE    (A0)+,D0                        | GET LEFT COORD
        MOVE    (A1)+,D1                        | GET RIGHT COORD
NEXT:
        CMP     D1,D0                           | IS NEXTA < NEXT B ?
        BLT.B   ALESS                           | YES, BRANCH
        BGT.B   BLESS                           | BR IF NEXTB IS LESS
        CMPI    #0x7FFF,D0                      | ARE WE AT THE END ?
        BEQ.B   SKIP2_EXIT                      | YES, QUIT
        CMP     D3,D2                           | ARE ASTATE AND BSTATE SAME ?
        BNE.B   SKIP0                           | NO, SKIP
        MOVE    D0,(A2)+                        | YES, PUT CHANGE
SKIP0:
        MOVE    (A0)+,D0                        | GET RIGHT COORD
        NOT     D2                              | TOGGLE ASTATE
        MOVE    (A1)+,D1                        | GET NEW NEXTB
        NOT     D3                              | TOGGLE BSTATE
        BRA.B   NEXT                            | LOOP FOR MORE
ALESS:
        TST     D3                              | TEST BSTATE
        BEQ.B   SKIP1                           | SKIP IF NOT TRUE
        MOVE    D0,(A2)+                        | PUT NEXTA
SKIP1:
        MOVE    (A0)+,D0                        | PUT RIGHT COORD
        NOT     D2                              | AND TOGGLE ASTATE
        BRA.B   NEXT                            | LOOP FOR MORE
BLESS:
        TST     D2                              | TEST ASTATE
        BEQ.B   SKIP2                           | SKIP IF NOT TRUE
        MOVE    D1,(A2)+                        | PUT NEXTB
SKIP2:
        MOVE    (A1)+,D1                        | GET NEW NEXTB
        NOT     D3                              | AND TOGGLE BSTATE
        BRA.B   NEXT                            | LOOP FOR MORE
SKIP2_EXIT:
        MOVE    #0x7FFF,(A2)+                   | PUT END MARKER INTO DST
        RTS                                     | return from SectScan/DiffScan/UnionScan

| ----------------------------------------------------------
| .PROC InsetScan,3
| PROCEDURE InsetScan(src,dst: ScanPtr; dh: INTEGER);
| Horizontally inset an inversion scan by dh (outset if dh < 0).
| The input scan is a sorted array of integers terminated by 32767.
| The output scan contains the inversion coordinates for the inset.
| INPUTS: A0 SRC, A2 DST, D2 DH. CLOBBERS D0-D1/A0-A2.
| (RgnOp op 8, used by InsetRgn.)
InsetScan:
        TST     D2                              | IS DH NEG ?
        BLT.B   OUTSET                          | YES, OUTSET
INSET:
        CMPI    #0x7FFF,(A0)                    | CHECK FOR TERMINATOR
        BEQ.B   OUTLOOP_CONT_2                  | QUIT WHEN FOUND
        MOVE    (A0)+,D0                        | GET LEFT COORD
        MOVE    (A0)+,D1                        | GET RIGHT COORD
        ADD     D2,D0                           | ADD DH TO LEFT
        SUB     D2,D1                           | SUB DH FROM RIGHT
        CMP     D1,D0                           | IS LEFT >= RIGHT ?
        BGE.B   INSET                           | YES, SKIP BOTH (collapsed pair)
        MOVE    D0,(A2)+                        | PUT LEFT COORD TO DST
        MOVE    D1,(A2)+                        | PUT RIGHT COORD TO DST
        BRA.B   INSET                           | LOOP ENTIRE SCAN
OUTSET:
        MOVEA.W #0x8001,A1                      | A1 = sentinel (prev right = INT_MIN)
        BRA.B   OUTLOOP_CHECK_END               | -> end-of-row check
OUTLOOP:
        MOVE    (A0)+,D0                        | GET LEFT COORD
        MOVE    (A0)+,D1                        | GET RIGHT COORD
        ADD     D2,D0                           | ADD DH TO LEFT
        SUB     D2,D1                           | SUB DH FROM RIGHT
        CMP     A1,D0                           | IS LEFT <= OLDRIGHT ?
        BGT.B   OUTLOOP_NO                      | NO, CONTINUE
        SUBQ.W  #0x2,A2                         | OVER-WRITE PREVIOUS RIGHT
        BRA.B   OUTLOOP_CONT                    | AND CONTINUE
OUTLOOP_NO:
        MOVE    D0,(A2)+                        | OUTOK: PUT LEFT COORD
OUTLOOP_CONT:
        MOVE    D1,(A2)+                        | OUTOK2: PUT RIGHT COORD
        MOVE    D1,A1                           | OLDRIGHT := RIGHT
OUTLOOP_CHECK_END:
        CMPI    #0x7FFF,(A0)                    | START: CHECK FOR TERMINATOR
        BNE.B   OUTLOOP                         | AND LOOP ENTIRE SCAN
OUTLOOP_CONT_2:
        MOVE    #0x7FFF,(A2)+                   | COPY JPTR^ TO IPTR^
        RTS                                     | return from InsetScan/OutSet
