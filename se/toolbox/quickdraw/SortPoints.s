| ------------------------------------------------------------------
|
| --> SORTPOINTS.TEXT
|
| Routines to sort inversion points and cull duplicates.

| -------------------------------------------------------------
|
| PROCEDURE SortPoints(ptBuf: PointsPtr; ptCount: INTEGER);
|
| Performs a non-recursive Quicksort on an array of points to
| put them in increasing Vert.Horiz order. Re-written 5 Sept 83
| to cut down worst-case stack usage.
|   See Algorithms + Data Structures = Programs, p.80.
|
| A6 offsets of params after LINK:
|   PARAMSIZE = 6
|   PTBUF     = PARAMSIZE+8-4  (LONG)
|   PTCOUNT   = PTBUF-2        (WORD)
|
SORTPOINTS:
    LINK        A6,#0x0                         | no local variables
    MOVEM.L     D3-D4/A2-A4,-(A7)               | save regs
    MOVEA.L     0xA(A6),A3                      | LeftPtr := start of pt array
    MOVE.W      A3,D3                           | copy LeftPtr low bits
    ANDI.W      #0x3,D3                         | set up LoBits for sort
    MOVEQ.L     #0x0,D0                         | clear for word load
    MOVE.W      0x8(A6),D0                      | get PtCount
    BLE.B       SORTPOINTS_GOHOME               | do nothing if no points
    LSL.L       #0x2,D0                         | quad PtCount for bytes
    MOVEA.L     A3,A4                           | copy LeftPtr
    ADDA.L      D0,A4                           | add to dstStart
    SUBQ.W      #0x4,A4                         | RightPtr := dstEnd - 4
    MOVE.L      A7,D4                           | remember stack marker
    MOVEM.L     A3-A4,-(A7)                     | push LeftPtr and RightPtr
SORTPOINTS_LOOP:
    MOVEM.L     (A7)+,A3-A4                     | pop LeftPtr and RightPtr
SPLIT:
    MOVEA.L     A3,A1                           | IPtr := LeftPtr
    MOVEA.L     A4,A2                           | JPtr := RightPtr
|
| Calc MidPtr and MidPt
|
    MOVE.L      A3,D0                           | add LeftPtr
    ADD.L       A4,D0                           | and RightPtr
    ROXR.L      #0x1,D0                         | then divide by 2 for MidPtr
    ANDI.W      #0xFFFC,D0                      | trunc to multiple of 4 bytes
    OR.W        D3,D0                           | OR in LoBits for point boundary
    MOVEA.L     D0,A0                           | get MidPtr into A-reg
    MOVE.W      0x2(A0),D1                      | get MidPt.h
    MOVE.W      (A0),D2                         | and MidPt.v
|
| While IPtr^ < MidPt do bump IPtr to right
|
SPLIT_RETRY:
    BRA.B       SPLIT_LOOP                      | go to loop start
| ----------------------------------------------------------
|
| SPLIT_NEXT -- bump IPtr right while IPtr^ < MidPt
|
SPLIT_NEXT:
    ADDQ.W      #0x4,A1                         | bump IPtr to right
SPLIT_LOOP:
    CMP.W       (A1),D2                         | is MidPt.v > IPtr^.v ?
    BGT.B       SPLIT_NEXT                      | yes, bump some more
    BLT.B       THREE                           | br if done with IPtr
    CMP.W       0x2(A1),D1                      | if same vert, look at horiz
    BGT.B       SPLIT_NEXT                      | keep bumping if MidPt.h > IPtr^.h
|
| While JPtr^ > MidPt do bump JPtr to left
|
THREE:
    BRA.B       SPLIT_LOOP_2                    | go to loop start
| ----------------------------------------------------------
|
| FOUR -- bump JPtr left while JPtr^ > MidPt
|
FOUR:
    SUBQ.W      #0x4,A2                         | bump JPtr to left
SPLIT_LOOP_2:
    CMP.W       (A2),D2                         | is MidPt.v < JPtr^.v ?
    BLT.B       FOUR                            | yes, bump some more
    BGT.B       SPLIT_DONE_2                    | br if done bumping JPtr
    CMP.W       0x2(A2),D1                      | if same vert, look at horiz
    BLT.B       FOUR                            | keep bumping if MidPt.h < JPtr^.h
|
| If IPtr <= JPtr then swap IPtr^ and JPtr^, and bump both pointers
|
SPLIT_DONE_2:
    CMPA.L      A2,A1                           | is IPtr > JPtr ?
    BGT.B       SORTPOINTS_NOSWAP               | yes, all done
    MOVE.L      (A1),D0                         | read IPtr^ into temp
    MOVE.L      (A2),(A1)                       | copy JPtr^ to IPtr^
    MOVE.L      D0,(A2)                         | swap points
    ADDQ.W      #0x4,A1                         | bump IPtr to right
    SUBQ.W      #0x4,A2                         | bump JPtr to left
|
| Repeat until this partitioning is complete (IPtr > JPtr)
|
SORTPOINTS_NOSWAP:
    CMPA.L      A2,A1                           | is IPtr > JPtr ?
    BLS.B       SPLIT_RETRY                     | no, loop again
|
| If i < right then stack request to sort right partition
|
    CMPA.L      A4,A1                           | is IPtr < RightPtr ?
    BCC.B       SORTPOINTS_RIGHTOK              | yes, continue
    MOVEM.L     A1/A4,-(A7)                     | no, push IPtr, RightPtr
SORTPOINTS_RIGHTOK:
    MOVEA.L     A2,A4                           | RightPtr := JPtr
    CMPA.L      A4,A3                           | is LeftPtr >= RightPtr ?
    BCS.B       SPLIT                           | no, partition again
    CMPA.L      D4,A7                           | is stack empty yet ?
    BNE.B       SORTPOINTS_LOOP                 | no, loop for more
SORTPOINTS_GOHOME:
    MOVEM.L     (A7)+,D3-D4/A2-A4               | restore regs
    UNLK        A6                              | restore A6
    MOVEA.L     (A7)+,A0                        | pop return address
    ADDQ.W      #0x6,A7                         | strip 6 bytes of params
    JMP         (A0)                            | tail-call return from SORTPOINTS_GOHOME via A0
| -------------------------------------------------------------
|
| PROCEDURE CullPoints(ptBuf: PointsPtr; VAR ptCount: INTEGER);
|
| Cancel any duplicate pairs of points in an array of points.
|
| A6 offsets of params after LINK:
|   PARAMSIZE = 8
|   PTBUF     = PARAMSIZE+8-4  (LONG)
|   PTCOUNT   = PTBUF-4        (LONG, VAR)
|
CULLPOINTS:
    LINK        A6,#0x0                         | no local variables
    MOVEM.L     D0-D7/A1-A5,-(A7)               | save regs
    MOVEA.L     0x8(A6),A0                      | get VAR addr of PtCount
    MOVE.W      (A0),D0                         | get PtCount
    BLE.W       CULLPOINTS_GOHOME               | do nothing if no points
    MOVEA.L     0xC(A6),A1                      | SrcPtr := start ptr
    MOVEA.L     A1,A3                           | copy start
    EXT.L       D0                              | clear hi word
    LSL.L       #0x2,D0                         | quad PtCount for bytes
    ADDA.L      D0,A3                           | add to start
    SUBQ.W      #0x4,A3                         | last point is at end-4
    MOVE.L      A1,D5                           | save start for later
    MOVEA.L     A1,A2                           | DstPtr := start
    BRA.B       CULLPOINTS_WHILE1               | go to loop start
| ----------------------------------------------------------
|
| DELETE -- src pair was duplicate, drop both
|
DELETE:
    ADDQ.W      #0x4,A1                         | skip over both src points
    BRA.B       CULLPOINTS_WHILE1               | go to loop start
| ----------------------------------------------------------
|
| CULLPOINTS_MORE1 -- compare current src to next; cancel if same
|
CULLPOINTS_MORE1:
    MOVE.L      (A1)+,D0                        | get current src point
    CMP.L       (A1),D0                         | is it same as next ?
    BEQ.B       DELETE                          | yes, delete both
    MOVE.L      D0,(A2)+                        | no, copy to dst
CULLPOINTS_WHILE1:
    CMPA.L      A3,A1                           | is SrcPtr < LastPtr ?
    BLT.B       CULLPOINTS_MORE1                | yes, go for more
    BGT.B       CULLPOINTS_DONE                 | br if done
    MOVE.L      (A1)+,(A2)+                     | finish up last point
CULLPOINTS_DONE:
    MOVE.L      A2,D0                           | get dst ptr
    SUB.L       D5,D0                           | subtract start ptr
    LSR.W       #0x2,D0                         | div by 4 for PtCount
    MOVEA.L     0x8(A6),A0                      | get VAR addr
    MOVE.W      D0,(A0)                         | update PtCount to reflect deletions
CULLPOINTS_GOHOME:
    MOVEM.L     (A7)+,D0-D7/A1-A5               | restore regs
    UNLK        A6                              | restore A6
    MOVEA.L     (A7)+,A0                        | pop return address
    ADDQ.W      #0x8,A7                         | strip 8 bytes of params
    JMP         (A0)                            | tail-call return from CULLPOINTS_GOHOME via A0
