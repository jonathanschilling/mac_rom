| --> PACKRGN.TEXT
|
| PackRgn: pack sorted inversion points into a region.
| Apple source: PackRgn.a (1983 QuickDraw sources).

PackRgn:
        LINK    A6,#-0x8                        | allocate 8-byte BBOX local
        MOVEM.L D0-D7/A1-A4,-(SP)               | SAVE REGS
        MOVE.L  14(A6),A4                       | get pt-buffer ptr
        MOVE.L  8(A6),A3                        | get rgnHandle
        MOVE    12(A6),D6                       | D6 := nPoints
        MOVE.L  (A3),A1                         | dereference rgnHandle
        MOVE    (A1),D5                         | D5 := old rgnSize
        MOVE.L  (A4),A0                         | A0 := scan-line ptr
        MOVE    #0xA,D7                         | rgnSize header = 10
        CLR.L   -8(A6)                          | clear BBOX top/left
        CLR.L   -4(A6)                          | clear BBOX bottom/right
        CMPI    #0x4,D6                         | test nPoints vs 4 (rect)
        BGT.B   PACKRGN_NO                      | more than rect: scan all points
        BLT.W   PACKRGN_DONE                    | fewer than 4: empty region
        MOVE.L  (A0),-8(A6)                     | BBOX TopLeft from scan
        MOVE.L  12(A0),-4(A6)                   | BBOX BotRight from scan
        BRA.W   PACKRGN_DONE                    | rect-only path done
PACKRGN_NO:
        MOVE    (A0),-8(A6)                     | BBOX top := first point V
        MOVE    2(A0),D1                        | D1 := initial MIN H
        MOVE    D1,D2                           | D2 := initial MAX H
        MOVE    D6,D3                           | D3 := loop counter (nPoints)
PACKRGN_LOOP:
        SUBQ.W  #0x1,D3                         | decrement counter
        BLT.B   ENDSCAN                         | done when negative
        MOVE.L  (A0)+,D0                        | get point (V,H)
        CMP     D1,D0                           | V < MIN H so far?
        BGE.B   PACKRGN_NO_2                    | no -> check max
        MOVE    D0,D1                           | yes, MIN := V
        BRA.B   PACKRGN_LOOP                    | next point
PACKRGN_NO_2:                                   | jump via A0
        CMP     D2,D0                           | V > MAX H so far?
        BLE.B   PACKRGN_LOOP                    | no, next point
        MOVE    D0,D2                           | yes, MAX := V
        BRA.B   PACKRGN_LOOP                    | next point
ENDSCAN:
        MOVE    D1,-6(A6)                       | BBOX LEFT:=MINH
        MOVE    D2,-2(A6)                       | BBOX RIGHT:=MAXH
        MOVE    -4(A0),-4(A6)                   | BBOX BOTTOM:=LAST POINT.V
        MOVEQ.L #0x3,D5                         | base size: rgnSize+bbox(8)+terminator
        ADD     D6,D5                           | add nPoints
        LSL     #0x2,D5                         | x4 (each point = 4 bytes)
        MOVE.L  A3,-(SP)                        | push rgnHandle
        MOVE    D5,-(SP)                        | push new size
        JSR     SetHSize(PC)                    | grow region handle to D5 bytes
        MOVE.L  (A4),A0                         | re-derefence point buffer
        MOVE.L  (A3),A1                         | re-dereference rgnHandle
        ADDA.W  #0xA,A1                         | skip past 10-byte header
        SUBQ.W  #0x1,D6                         | DBcc loop count = nPoints-1
        MOVE    (A0)+,D0                        | get first vert
        BRA.B   PACKRGN_START                   | jump to first store
NEXTPT:
        CMP     (A0)+,D0                        | same vertical as previous?
        BEQ.B   VSAME                           | yes, just emit horizontal
        MOVE    #0x7FFF,(A1)+                   | end-of-row terminator
        MOVE    -2(A0),D0                       | reload V into D0
PACKRGN_START:
        MOVE    D0,(A1)+                        | emit vertical coord
VSAME:
        MOVE    (A0)+,(A1)+                     | copy horizontal to packed rgn
        DBRA    D6,NEXTPT                       | loop for each point
        MOVE    #0x7FFF,(A1)+                   | end-of-row terminator
        MOVE    #0x7FFF,(A1)+                   | end-of-region terminator
        MOVE.L  (A3),A0                         | re-dereference rgnHandle
        SUBA.L   A0,A1                          | compute final size
        MOVE.W   A1,D7                          | D7 := actual rgnSize

| --------------------------------------------------------
| INSTALL RGNSIZE AND RGNBBOX.
| Called during boot (7,415 times in 30s trace).
PACKRGN_DONE:
        MOVE.L  (A3),A0                         | NXTVERT: GET VERT AND HORIZ COORDS
        MOVE    D7,(A0)+                        | PUT LEFT POINT TO DST
        MOVE.L  -8(A6),(A0)+                    | GET HORIZ COORD
        MOVE.L  -4(A6),(A0)+                    | PUT RIGHT POINT TO DST
        CMP     D7,D5                           | did size change vs original?
        BEQ.B   PACKRGN_SIZEOK                  | no, skip resize
        MOVE.L  A3,-(SP)                        | push rgnHandle
        MOVE    D7,-(SP)                        | push final size
        JSR     SetHSize(PC)                    | shrink to actual size
PACKRGN_SIZEOK:
        MOVEM.L (SP)+,D0-D7/A1-A4               | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return PC
        ADDA.W  #0xA,SP                         | strip PARAMSIZE bytes
        JMP     (A0)                            | RTS

