| ------------------------------------------------------------------
|
| --> SEEKRGN.TEXT
|
| Routines to play back a region into a scanline buffer.

| ------------------------------------------------------
|
| InitRgn -- initialize a region state record at top.
|
| INPUTS:  A0 = RgnPtr
|          A1 = state record
|          D0 = MinH
|          D1 = MaxH
|          D2 = BufLeft
|
| OUTPUTS: All fields of state record;
|          ScanBuf allocated on stack.
|
| CLOBBERS D0,D1,A0
|
| Called by: DRAWLINE_CLRMASK_CONT, RGNBLT_CLRMASK_CONT, CLRMASK_CONT, RECTINRGN, AGAIN (and 1 more)
INITRGN:
    MOVE.W      D0,0x12(A1)                     | install MinH
    MOVE.W      D1,0x14(A1)                     | install MaxH
    MOVE.W      D2,0x16(A1)                     | install LeftH
    MOVE.L      A0,(A1)                         | save region ptr
    MOVE.W      #0x8001,0xE(A1)                 | ThisV := -32767
    MOVE.W      0x2(A0),0x10(A1)                | NextV := RgnBBox.top
    LEA.L       0xA(A0),A0                      | point to first data
    MOVE.L      A0,0x4(A1)                      | init DataPtr
    MOVEA.L     (A7)+,A0                        | pop return addr
    SUB.W       D2,D1                           | calc buffer width in dots
    LSR.W       #0x5,D1                         | div by 32 for #longs - 1
    MOVE.W      D1,0xC(A1)                      | save ScanSize for later
INITRGN_CLRLOOP:
    CLR.L       -(A7)                           | allocate and clear buffer
    DBF.W       D1,INITRGN_CLRLOOP              | loop till done
    MOVE.L      A7,0x8(A1)                      | remember buffer start
    JMP         (A0)                            | tail-call return from INITRGN_CLRLOOP via A0
| ------------------------------------------------------------------
|
| SeekRgn(rgnState,vert)
|
| Routine to play back a region forward or backward until its scan
| buffer contains the bitmap for the given vertical coordinate.
|
| INPUTS:  A1 points to a region state record
|          D0 contains the desired vertical coord
|
| OUTPUTS: updates ThisV, NextV, DataPtr, and ScanBuf^ of state
|          record. D1->1 if change, 0 if no change. (Z-flag set
|          if no change.)
|
| CLOBBERS A0, D1
|
| Called by: BCLOOP_CONT, STRETCHBITS_GOHOME_CONT_ABC, DRAWLINE_JSRSEEK_CONT_3, JMPSEEK_CONT, JMPSEEK_CONT_2 (and 12 more)
SEEKRGN:
    CMP.W       0x10(A1),D0                     | is desired vert >= NextV ?
    BGE.B       DOWN                            | yes, bump downward
    CMP.W       0xE(A1),D0                      | is desired vert < current vert ?
    BLT.B       UP                              | yes, bump upward
    CLR.W       D1                              | else report no changes
    RTS                                         | and return
| -----------------------------------------------------
|
| To move upwards, just reset to start and move down.
|
UP:
    MOVEA.L     0x8(A1),A0                      | point to ScanBuf
    MOVE.W      0xC(A1),D1                      | get buffer size
SEEKRGN_CLRLP:
    CLR.L       (A0)+                           | clear a long
    DBF.W       D1,SEEKRGN_CLRLP                | loop entire ScanBuf
    MOVEA.L     (A1),A0                         | get region ptr
    MOVE.W      0x2(A0),0x10(A1)                | NextV := RgnBBox.top
    MOVE.W      #0x8001,0xE(A1)                 | ThisV := -32767
    LEA.L       0xA(A0),A0                      | point to start of region data
    MOVE.L      A0,0x4(A1)                      | reset DataPtr
    CMP.W       0x10(A1),D0                     | is desired vert >= NextV ?
    BLT.W       SEEKRGN_DONE                    | no, quit
| ------------------------------------------------------
|
| While desired vert >= NextV, bump down.
|
DOWN:
    MOVEM.L     D0-D6/A2-A3,-(A7)               | save regs
    MOVE.W      D0,D2                           | save vert
    MOVEA.L     0x4(A1),A2                      | point to vert coord
SEEKRGN_DOWN1:
    MOVE.W      (A2)+,0xE(A1)                   | update current vert
| -------------------------------------------------
|
| Get left and right horiz coords and trim against MinH and MaxH.
|
SEEKRGN_NEXTHOR:
    MOVE.W      (A2)+,D3                        | get left coord
    CMPI.W      #0x7FFF,D3                      | is it end-of-scanline ?
    BEQ.B       DONE1                           | yes, quit
    MOVE.W      (A2)+,D4                        | get right coord
    CMP.W       0x12(A1),D4                     | is right <= MinH ?
    BLE.B       SEEKRGN_NEXTHOR                 | yes, ignore on left
    CMP.W       0x14(A1),D3                     | is left >= MaxH ?
    BGE.B       SEEKRGN_NEXTHOR                 | yes, ignore on right
    CMP.W       0x12(A1),D3                     | is left < MinH ?
    BGE.B       LOK                             | no, continue
    MOVE.W      0x12(A1),D3                     | yes, trim left
LOK:
    CMP.W       0x14(A1),D4                     | is right > MaxH ?
    BLE.B       ROK                             | no, continue
    MOVE.W      0x14(A1),D4                     | yes, trim right
ROK:
    SUB.W       0x16(A1),D3                     | make coords rel to buffer
    SUB.W       0x16(A1),D4                     | make right rel to buffer
| ------------------------------------------
|
| Get LeftMask and RightMask
|
    LEA.L       MASKTAB(PC),A0                  | point to mask table
    MOVEQ.L     #0xF,D0                         | get mask for lo 4 bits
    MOVE.W      D3,D5                           | copy left coord
    AND.W       D0,D5                           | calc left MOD 16
    ADD.W       D5,D5                           | double for index
    MOVE.W      0x0(A0,D5.W),D5                 | get left mask from table
    NOT.W       D5                              | invert for LeftMask
    MOVE.W      D4,D6                           | copy right coord
    AND.W       D0,D6                           | calc right MOD 16
    ADD.W       D6,D6                           | double for index
    MOVE.W      0x0(A0,D6.W),D6                 | get right mask from table
| ------------------------------------------
|
| Calc LeftWord, BufPtr, WordCount
|
    LSR.W       #0x4,D3                         | convert dots to words
    MOVEA.L     0x8(A1),A3                      | copy BufStart
    ADDA.W      D3,A3                           | add LeftWord offset
    ADDA.W      D3,A3                           | init BufPtr to LeftWord
    LSR.W       #0x4,D4                         | calc right DIV 16
    SUB.W       D3,D4                           | WordCount := RightWord - LeftWord
    BGT.B       NOTIN1                          | br if not all in one
| ------------------------------------------
|
| Left and right are all in one word.
|
    AND.W       D5,D6                           | combine left and right masks
    EOR.W       D6,(A3)                         | XOR combination into buffer
    BRA.B       SEEKRGN_NEXTHOR                 | go for more dh's this scan
| ------------------------------------------
|
| NOT ALL IN ONE WORD. Do left, middle if any, then right.
|
NOTIN1:
    EOR.W       D5,(A3)+                        | XOR LeftMask into buffer
    BRA.B       INVLONG_CONT                    | see if any full words
| ----------------------------------------------------------
|
| INVLONG -- middle words: invert two whole words at a time
|
INVLONG:
    NOT.L       (A3)+                           | invert 2 whole words
INVLONG_CONT:
    SUBQ.W      #0x2,D4                         | adjust WordCount
    BGT.B       INVLONG                         | yes, at least 2
    BLT.B       ENDWORD                         | no, finish up last with mask
    NOT.W       (A3)+                           | yes, do last full word
ENDWORD:
    EOR.W       D6,(A3)                         | XOR RightMask into buffer
    BRA.B       SEEKRGN_NEXTHOR                 | go for more dh's this scan
| ----------------------------------------------------------
|
| DONE1 -- end-of-scanline marker hit; advance NextV
|
DONE1:
    MOVE.L      A2,0x4(A1)                      | update DataPtr
    MOVE.W      (A2),0x10(A1)                   | update next vert
    CMP.W       0x10(A1),D2                     | is desired vert >= NextV ?
    BGE.W       SEEKRGN_DOWN1                   | yes, bump down some more
    MOVEM.L     (A7)+,D0-D6/A2-A3               | restore regs
SEEKRGN_DONE:
    MOVEQ.L     #0x1,D1                         | report scanline changed
    RTS                                         | and return
