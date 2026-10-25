| -----------------------------------------------------------
|
| --> PUTOVAL.TEXT
|
| Routine to add the inversion points for an oval to a region.

| ----------------------------------------------------------
| PutOval -- internal RoundRect/Oval drawing helper.
| Called from StdRRect (line 365) and StdOval (line 480).
| Takes 3 params: rect handle (16(A6)) + 2 offset words
| (8(A6), 12(A6)) -- used to scale dimensions for oval overlay.
| NOT _TEDispose -- that lives in textedit.s. Earlier mass-rename
| pass mislabeled this.
PutOval:
        LINK    A6,#-0x32                       | set up stack frame
        MOVEM.L D0-D7/A1-A5,-(SP)               | save scratch regs to stack
        MOVE.L  16(A6),A3                       | A3 := maskRgn
        MOVE.L  (A3),A3                         | A3 := (A3)
        MOVE.L  A3,A2                           | A2 := A3
        MOVE.L  12(A6),A0                       | A0 := mode
        ADDA.W  (A0),A3                         | A3 += (A0)
        MOVE.L  A2,A1                           | A1 := A2
        MOVE.L  8(A6),A0                        | A0 := pat
        ADDA.W  (A0),A1                         | A1 += (A0)
        MOVE.L  24(A6),-(SP)                    | -(SP) := srcRgn
        PEA.L     -0x2A(A6)                     | push effective addr -0x2A(A6)
        MOVE    22(A6),-(SP)                    | push 22(A6)
        MOVE    20(A6),-(SP)                    | -(SP) := dstRgn
        JSR     InitOval(PC)                    | call InitOval
        MOVE    -0x24(A6),-0x30(A6)             | jump via A0
        MOVE    -0x20(A6),-0x32(A6)             | -0x32(A6) := -0x20(A6)
        MOVE    20(A6),D0                       | D0 := dstRgn
        ASR     #0x1,D0                         | D0 >>= 1 (arith)
        ADD     -0x2A(A6),D0                    | D0 += -0x2A(A6)
        MOVE    D0,-0x2C(A6)                    | -0x2C(A6) := D0
        MOVE.L  24(A6),A0                       | A0 := srcRgn
        ADD     4(A0),D0                        | D0 += 4(A0)
        SUB     (A0),D0                         | D0 -= (A0)
        SUB     20(A6),D0                       | D0 -= 20(A6)
        MOVE    D0,-0x2E(A6)                    | -0x2E(A6) := D0
        MOVE    -0x2A(A6),D6                    | D6 := -0x2A(A6)
        MOVE    -0x30(A6),D5                    | D5 := -0x30(A6)
        JSR     PUTPT(PC)                       | call PUTPT
        MOVE    -0x32(A6),D5                    | D5 := -0x32(A6)
        JSR     PUTPT(PC)                       | call PUTPT
NXTVERT:
        CMP     -0x2C(A6),D6                    | compare D6 with -0x2C(A6)
        BLT.B   PUTOVAL_YESBUMP                 | if signed < -> PUTOVAL_YESBUMP
        CMP     -0x2E(A6),D6                    | compare D6 with -0x2E(A6)
        BLT.B   PUTOVAL_YESBUMP_SKIP            | if signed < -> PUTOVAL_YESBUMP_SKIP
PUTOVAL_YESBUMP:
        PEA.L     -0x2A(A6)                     | push effective addr -0x2A(A6)
        MOVE    D6,-(SP)                        | push D6
        JSR     BumpOval(PC)                    | call BumpOval
        MOVE    -0x24(A6),D5                    | D5 := -0x24(A6)
        CMP     -0x30(A6),D5                    | compare D5 with -0x30(A6)
        BEQ.B   PUTOVAL_YESBUMP_OK              | if zero -> PUTOVAL_YESBUMP_OK
        JSR     PUTPT(PC)                       | call PUTPT
        MOVE    -0x30(A6),D5                    | D5 := -0x30(A6)
        JSR     PUTPT(PC)                       | call PUTPT
        MOVE    -0x24(A6),-0x30(A6)             | -0x30(A6) := -0x24(A6)
PUTOVAL_YESBUMP_OK:
        MOVE    -0x20(A6),D5                    | D5 := -0x20(A6)
        CMP     -0x32(A6),D5                    | compare D5 with -0x32(A6)
        BEQ.B   PUTOVAL_YESBUMP_SKIP            | if zero -> PUTOVAL_YESBUMP_SKIP
        JSR     PUTPT(PC)                       | call PUTPT
        MOVE    -0x32(A6),D5                    | D5 := -0x32(A6)
        JSR     PUTPT(PC)                       | call PUTPT
        MOVE    -0x20(A6),-0x32(A6)             | -0x32(A6) := -0x20(A6)
PUTOVAL_YESBUMP_SKIP:
        ADDQ.W  #0x1,D6                         | D6 += #0x1
        CMP     -0x28(A6),D6                    | compare D6 with -0x28(A6)
        BLT.B   NXTVERT                         | if signed < -> NXTVERT
        MOVE    -0x30(A6),D5                    | D5 := -0x30(A6)
        JSR     PUTPT(PC)                       | call PUTPT
        MOVE    -0x32(A6),D5                    | D5 := -0x32(A6)
        JSR     PUTPT(PC)                       | call PUTPT
        SUBA.L  A2,A3                           | A3 -= A2
        MOVE.L  12(A6),A0                       | A0 := mode
        MOVE    A3,(A0)                         | (A0) := A3
        MOVEM.L (SP)+,D0-D7/A1-A5               | restore scratch regs from stack
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address into A0
        ADDA.W  #0x14,SP                        | pop parameter bytes from stack
        JMP     (A0)                            | RTS

| -----------------------------------------------------------------------
| Local routine to Append a point to the end of the saved points buffer,
| extending buffer if necessary. If pt is a duplicate of the last pt,
| cancel both instead.
| INPUTS: D5: HORIZ COORD
| D6: VERT COORD
| A1: BUFLIMIT GETS EXPANDED AND RELOCATED
| A2: BUFSTART GETS RELOCATED
| A3: BUFPTR GETS BUMPED AND RELOCATED
| ALTERS: A1,A2,A3, VAR SIZE
| Called during boot.
PUTPT:
        CMPA.L  A1,A3                           | compare A3 with A1
        BLT.B   PUTOVAL_SIZEOK                  | if signed < -> PUTOVAL_SIZEOK
        SUBA.L  A2,A3                           | A3 -= A2
        SUBA.L  A2,A1                           | A1 -= A2
        ADDA.W  #0x400,A1                       | A1 += #0x400
        MOVEM.L D0-A3,-(SP)                     | save scratch regs to stack
        MOVE.L  8(A6),A0                        | PUT HORIZ COORD
        MOVE    A1,(A0)                         | (A0) := A1
        MOVE.L  16(A6),-(SP)                    | -(SP) := maskRgn
        MOVE    A1,-(SP)                        | push A1
        JSR     SetHSize(PC)                    | call SetHSize
        MOVEM.L (SP)+,D0-A3                     | restore scratch regs from stack
        MOVE.L  16(A6),A2                       | A2 := maskRgn
        MOVE.L  (A2),A2                         | A2 := (A2)
        ADDA.L  A2,A3                           | A3 += A2
        ADDA.L  A2,A1                           | A1 += A2
| -------------------------------------------------------------------
| ADD NEW POINT TO THE SAVE BUFFER UNLESS IT MATCHED THE PREVIOUS PT.
| DELETE DUPLICATE POINTS SINCE THEY WILL CANCEL EACH OTHER ANYWAY.
| Called during boot.
PUTOVAL_SIZEOK:
        CMPA.L  A2,A3                           | compare A3 with A2
        BEQ.B   APPEND                          | if zero -> APPEND
        CMP     -2(A3),D5                       | compare D5 with -2(A3)
        BNE.B   APPEND                          | if non-zero -> APPEND
        CMP     -4(A3),D6                       | compare D6 with -4(A3)
        BNE.B   APPEND                          | if non-zero -> APPEND
        SUBQ.W  #0x4,A3                         | A3 -= #0x4
        RTS                                     | return from PUTOVAL_SIZEOK

| ----------------------------------------------------------
| APPEND -- append (vert,horiz) point pair to region build buffer.
| Used by PUTOVAL_SIZEOK helper in RgnBlt.s. In Plus this small
| helper lives at the tail of PutOval.s as `APPEND:`.
| Inputs: D6 = vert, D5 = horiz, A3 = bufPtr.
APPEND:
        MOVE    D6,(A3)+                        | PUT VERT COORD
        MOVE    D5,(A3)+                        | PUT HORIZ COORD
        RTS                                     | return from APPEND
