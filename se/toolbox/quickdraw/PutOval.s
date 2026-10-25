| -----------------------------------------------------------
|
| --> PUTOVAL.TEXT
|
| Routine to add the inversion points for an oval to a region.

| .PROC PUTOVAL,6
| .REF INITOVAL,BUMPOVAL,SETSIZE
| ----------------------------------------------------------------
|
| PROCEDURE PutOval(dstRect: Rect; ovalWidth,ovalHeight: INTEGER;
|                   bufHandle: Handle; VAR index,size: INTEGER);
|
| Create region inversion points for an oval or roundRect.
| ------------------------------------------------
|
| A6 OFFSETS OF PARAMETERS AFTER LINK:
|   DSTRECT +0x18 long, OVALWIDTH +0x16 word, OVALHEIGHT +0x14 word,
|   BUFHANDLE +0x10 long, INDEX +0xC long, SIZE +0x8 long
|
| Locals (-0x36-byte frame):
|   OVAL record at -0x2E (top, bot, y, rsq*ysq, square[8], oddNum[8],
|                         oddBump[8], leftEdge[4], rightEdge[4], oneHalf[4])
|   SKIPTOP -0x30, SKIPBOT -0x32, OLDLEFT -0x34, OLDRIGHT -0x36
|
| Called during boot.
PUTOVAL:
    LINK	A6,#-0x36                              | ALLOCATE LOCAL VARS
    MOVEM.L	D0-D7/A1-A5,-(A7)                   | SAVE REGS
| ---------------------------------------------------------------
|
| INIT AN OVAL RECORD
|
    MOVEA.L	0x18(A6),A0                         | POINT TO DSTRECT
    LEA.L	-0x2E(A6),A1                          | POINT TO OVAL RECORD
    MOVE.W	0x16(A6),D2                          | GET OVALWIDTH
    MOVE.W	0x14(A6),D1                          | GET OVALHEIGHT
    JSR	INITOVAL(PC)                            | INIT OVAL RECORD
    MOVE.W	-0xC(A6),-0x34(A6)                   | OLDLEFT := LEFTEDGE
    MOVE.W	-0x8(A6),-0x36(A6)                   | OLDRIGHT := RIGHTEDGE
    MOVE.W	0x14(A6),D0                          | GET OVALHEIGHT
    ASR.W	#0x1,D0                               | CALC OVAL HEIGHT DIV 2
    ADD.W	-0x2E(A6),D0                          | ADD OVAL TOP
    MOVE.W	D0,-0x30(A6)                         | SAVE SKIPTOP
    MOVEA.L	0x18(A6),A0                         | POINT TO DSTRECT
    ADD.W	0x4(A0),D0                            | ADD BOTTOM
    SUB.W	(A0),D0                               | SUBTRACT TOP
    SUB.W	0x14(A6),D0                           | SUBTRACT OVALHEIGHT
    MOVE.W	D0,-0x32(A6)                         | SAVE SKIPBOT
| -----------------------------------------------------------------
|
| GET BUF HANDLE, DE-REFERENCE IT, AND ADD INDEX
|
    MOVEA.L	0x10(A6),A3                         | GET HANDLE
    MOVEA.L	(A3),A3                             | DE-REFERENCE IT
    MOVEA.L	A3,A2                               | REMEMBER BUFSTART FOR LATER
    MOVEA.L	0xC(A6),A0                          | GET ADDR OF INDEX
    ADDA.W	(A0),A3                              | ADD INDEX TO BUFPTR
| ----------------------------------------------------------
|
| BUFLIMIT := BUFSTART + BUFSIZE
|
    MOVEA.L	A2,A1                               | GET BUFSTART
    MOVEA.L	0x8(A6),A0                          | GET ADDR OF SIZE
    ADDA.W	(A0),A1                              | LEAVE BUFLIMIT IN A1
    MOVE.W	-0x2E(A6),D6                         | D6 := OVAL TOP (VERT)
| ------------------------------------------------
|
| PUT THE TOP EDGE
|
    MOVE.W	-0x34(A6),D5                         | D5 := OLDLEFT
    JSR	PUTPT(PC)                               | PUTPOINT (OLDLEFT,VERT)
    MOVE.W	-0x36(A6),D5                         | D5 := OLDRIGHT
    JSR	PUTPT(PC)                               | PUTPOINT (OLDRIGHT,VERT)
| -----------------------------------------------------
|
| FOR EACH VERTICAL, BUMP LEFTEDGE AND RIGHTEDGE.
| IF THEY DIFFER FROM OLDLEFT AND OLDRIGHT, PUT INVERSION
| POINTS FOR THE DIFFERENCES
|
| Called during boot.
NXTVERT:
    CMP.W	-0x30(A6),D6                          | IS VERT < SKIPTOP ?
    BLT.B	PUTOVAL_YESBUMP                       | YES, BUMP OVAL RECORD
    CMP.W	-0x32(A6),D6                          | IS VERT >= SKIPBOT ?
    BLT.B	PUTOVAL_YESBUMP_SKIP                  | NO, SKIP BUMPING
PUTOVAL_YESBUMP:
    MOVEM.L	D6/A1-A3,-(A7)                      | YESBUMP: PRESERVE REGS
    LEA.L	-0x2E(A6),A3                          | POINT TO OVAL RECORD
    MOVE.W	D6,D0                                | GET CURRENT VERT
    JSR	BUMPOVAL(PC)                            | BUMP IT TO NEXT SCANLINE
    MOVEM.L	(A7)+,D6/A1-A3                      | RESTORE REGS
    MOVE.W	-0xC(A6),D5                          | D5 := NEW LEFTEDGE
| CHECK LEFT EDGE AND PUT TWO INVERSION POINTS IF IT HAS CHANGED
    CMP.W	-0x34(A6),D5                          | SAME AS OLDLEFT ?
    BEQ.B	PUTOVAL_YESBUMP_OK                    | YES, CONTINUE
    JSR	PUTPT(PC)                               | PUTPOINT (NEWLEFT,VERT)
    MOVE.W	-0x34(A6),D5                         | D5 := OLDLEFT
    JSR	PUTPT(PC)                               | PUTPOINT (OLDLEFT,VERT)
    MOVE.W	-0xC(A6),-0x34(A6)                   | UPDATE OLDLEFT
PUTOVAL_YESBUMP_OK:
    MOVE.W	-0x8(A6),D5                          | D5 := NEW RIGHTEDGE
| CHECK RIGHT EDGE AND PUT TWO INVERSION POINTS IF IT HAS CHANGED
    CMP.W	-0x36(A6),D5                          | SAME AS OLDRIGHT ?
    BEQ.B	PUTOVAL_YESBUMP_SKIP                  | YES, CONTINUE
    JSR	PUTPT(PC)                               | PUTPOINT (NEWRIGHT,VERT)
    MOVE.W	-0x36(A6),D5                         | D5 := OLDRIGHT
    JSR	PUTPT(PC)                               | PUTPOINT (OLDRIGHT,VERT)
    MOVE.W	-0x8(A6),-0x36(A6)                   | UPDATE OLDRIGHT
PUTOVAL_YESBUMP_SKIP:
    ADDQ.W	#0x1,D6                              | BUMP VERT
    CMP.W	-0x2C(A6),D6                          | IS VERT < OVAL BOTTOM ?
    BLT.B	NXTVERT                               | LOOP FOR ALL VERTICALS
| ------------------------------------------------
|
| PUT THE BOTTOM EDGE
|
    MOVE.W	-0x34(A6),D5                         | D5 := OLDLEFT
    JSR	PUTPT(PC)                               | PUTPOINT (OLDLEFT,VERT)
    MOVE.W	-0x36(A6),D5                         | D5 := OLDRIGHT
    JSR	PUTPT(PC)                               | PUTPOINT (OLDRIGHT,VERT)
    SUBA.L	A2,A3                                | NEW INDEX := BUFPTR - BUFSTART
    MOVEA.L	0xC(A6),A0                          | GET ADDR OF INDEX
    MOVE.W	A3,(A0)                              | UPDATE INDEX
    MOVEM.L	(A7)+,D0-D7/A1-A5                   | RESTORE REGS
    UNLK	A6                                     | DESTROY STACK FRAME
    MOVEA.L	(A7)+,A0                            | POP RETURN ADDRESS
    ADDA.W	#0x14,A7                             | STRIP 20 BYTES OF PARAMETERS
    JMP	(A0)                                    | RETURN TO CALLER
| -----------------------------------------------------------------------
|
| Local routine to Append a point to the end of the saved points buffer,
| extending buffer if necessary. If pt is a duplicate of the last pt,
| cancel both instead.
|
| INPUTS: D5: HORIZ COORD
| D6: VERT COORD
| A1: BUFLIMIT GETS EXPANDED AND RELOCATED
| A2: BUFSTART GETS RELOCATED
| A3: BUFPTR GETS BUMPED AND RELOCATED
|
| ALTERS: A1,A2,A3, VAR SIZE
|
| Called during boot.
| -----------------------------------------------------------------------
|
| Local routine to Append a point to the end of the saved points buffer,
| extending buffer if necessary. If pt is a duplicate of the last pt,
| cancel both instead.
|
| INPUTS: D5: HORIZ COORD
|         D6: VERT COORD
|         A1: BUFLIMIT GETS EXPANDED AND RELOCATED
|         A2: BUFSTART GETS RELOCATED
|         A3: BUFPTR GETS BUMPED AND RELOCATED
|
| ALTERS: A1,A2,A3, VAR SIZE
|
| Called during boot.
PUTPT:
    CMPA.L	A1,A3                                | IS BUFPTR < BUFLIMIT ?
    BLT.B	PUTOVAL_SIZEOK                        | YES, CONTINUE
| ---------------------------------------------------------------------
|
| BUFFER IS FULL, CALL STORAGE ALLOCATOR TO MAKE ROOM FOR 256 MORE POINTS.
| UPDATE BUFPTR, BUFSTART, BUFLIMIT, AND BUFSIZE AFTER RELOCATION.
|
    SUBA.L	A2,A3                                | MAKE BUFPTR RELATIVE
    SUBA.L	A2,A1                                | MAKE BUFLIMIT RELATIVE
    ADDA.W	#0x400,A1                            | MAKE BUFLIMIT BIGGER
    MOVEM.L	D0-D7/A0-A3,-(A7)                   | SAVE REGS
    MOVEA.L	0x8(A6),A0                          | GET ADDR OF SIZE
    MOVE.W	A1,(A0)                              | UPDATE BUFFER SIZE
    MOVE.L	0x10(A6),-(A7)                       | PUSH HANDLE PARAM
    MOVE.W	A1,-(A7)                             | PUSH NEW SIZE
    JSR	SETHSIZE(PC)                            | MAKE THE BUFFER BIGGER
    MOVEM.L	(A7)+,D0-D7/A0-A3                   | RESTORE REGS
    MOVEA.L	0x10(A6),A2                         | GET BUF HANDLE
    MOVEA.L	(A2),A2                             | GET NEW BUFSTART
    ADDA.L	A2,A3                                | MAKE BUFPTR UN-RELATIVE
    ADDA.L	A2,A1                                | MAKE BUFLIMIT UN-RELATIVE
| -------------------------------------------------------------------
|
| ADD NEW POINT TO THE SAVE BUFFER UNLESS IT MATCHED THE PREVIOUS PT.
| DELETE DUPLICATE POINTS SINCE THEY WILL CANCEL EACH OTHER ANYWAY.
|
| Called during boot.
PUTOVAL_SIZEOK:
    CMPA.L	A2,A3                                | SIZEOK: IS BUFPTR=STARTPTR ?
    BEQ.B	APPEND                                | BR IF FIRST POINT
    CMP.W	-0x2(A3),D5                           | DOES HORIZ MATCH PREV ?
    BNE.B	APPEND                                | NO, APPEND NEW POINT
    CMP.W	-0x4(A3),D6                           | DOES VERT MATCH PREV ?
    BNE.B	APPEND                                | NO, APPEND NEW POINT
    SUBQ.W	#0x4,A3                              | YES, DELETE DUPLICATE PAIR
    RTS                                         | AND RETURN
| ----------------------------------------------------------
|
| APPEND
|
| Called during boot.
APPEND:
    MOVE.W	D6,(A3)+                             | PUT VERT COORD
    MOVE.W	D5,(A3)+                             | PUT HORIZ COORD
    RTS                                         | AND RETURN
