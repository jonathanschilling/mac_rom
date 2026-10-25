| --> PUTRGN.TEXT
|
| PutRgn: add a region to the region being recorded.
| Apple source: PutRgn.a (1983 QuickDraw sources).

| ------------------------------------------------
| A6 OFFSETS OF PARAMETERS AFTER LINK:
| .PROC PUTRGN,4
| .REF SETSIZE
| ----------------------------------------------------------------
| PROCEDURE PutRgn(Rgn: RgnHandle; bufHandle: Handle; VAR index,size: INTEGER);
| Expands a region out to an array of inversion points.
PutRgn:
        LINK    A6,#0x0                         | NO LOCAL VARS
        MOVEM.L D7/A2-A4,-(SP)                  | SAVE REGS
        MOVE.L  16(A6),A4                       | A4 := bufHandle
        MOVE.L  20(A6),A3                       | A3 := rgnHandle
        MOVE.L  12(A6),A2                       | A2 := VAR index
        MOVE.L  (A3),A0                         | dereference rgnHandle
        MOVE    (A0),D7                         | D7 := rgnSize
        ADD     D7,D7                           | estimate buf bytes (rgnSize x2)
        ADD     (A2),D7                         | add current index
        MOVE.L  8(A6),A1                        | A1 := VAR size
        CMP     (A1),D7                         | does buffer fit?
        BLE.B   NOGROW                          | yes, skip grow
        ADDI    #0x100,D7                       | grow by 256 bytes
        MOVE    D7,(A1)                         | update VAR size
        MOVE.L  A4,-(SP)                        | push bufHandle
        MOVE    D7,-(SP)                        | YES, TRIM BOUNDS.BOTTOM
        JSR     SetHSize(PC)                    | grow point buffer
        MOVE.L  (A3),A0                         | re-deref rgnHandle
        MOVE.L  12(A6),A2                       | reload VAR index
NOGROW:
        MOVE.L  (A4),A1                         | DE-REFERENCE BUFHANDLE
        ADDA.W  (A2),A1                         | A1 += index
        CMPI    #0xA,(A0)                       | IS REGION RECTANGULAR ?
        BNE.B   PUTRGN_NOTRECT                  | NO, EXPAND IT
        ADDQ.W  #0x2,A0                         | skip rgnSize header
        MOVE.L  (A0)+,(A1)+                     | copy bbox top/left
        MOVE.L  (A0)+,(A1)+                     | copy bbox bottom/right
        BRA.B   PUTRGN_DONE                     | rect path done
PUTRGN_NOTRECT:
        LEA      10(A0),A0                      | skip past 10-byte header
PUTRGN_NXTVERT:
        MOVE.L   (A0)+,D7                       | get vertical coord (long)
NXTHOR:
        MOVE.L  D7,(A1)+                        | emit V to point buffer
        MOVE    (A0)+,D7                        | get next horizontal
        MOVE.L  D7,(A1)+                        | emit H to point buffer
        MOVE    (A0)+,D7                        | get next horizontal
        CMPI    #0x7FFF,D7                      | end-of-row terminator?
        BNE.B   NXTHOR                          | no, more horizontals
        CMPI    #0x7FFF,(A0)                    | end-of-region terminator?
        BNE.B   PUTRGN_NXTVERT                  | no, next scan line
PUTRGN_DONE:
        SUBA.L  (A4),A1                         | compute new index
        MOVE    A1,(A2)                         | update VAR index
        MOVEM.L (SP)+,D7/A2-A4                  | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return PC
        ADDA.W  #0x10,SP                        | strip PARAMSIZE bytes
        JMP     (A0)                            | RTS
