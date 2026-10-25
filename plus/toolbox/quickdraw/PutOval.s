| -----------------------------------------------------------
|
| --> PUTOVAL.TEXT
|
| Routine to add the inversion points for an oval to a region.
|

| ------------------------------------------------------
|
| OFFSETS IN AN OVAL STATE RECORD:
|

| .PROC PUTOVAL,6
| .REF INITOVAL,BUMPOVAL,SETSIZE
| ----------------------------------------------------------------
|
| PROCEDURE PutOval(dstRect: Rect; ovalWidth,ovalHeight: INTEGER;
| bufHandle: Handle; VAR index,size: INTEGER);
|
| Create region inversion points for an oval or roundRect.
| ------------------------------------------------
|
| A6 OFFSETS OF PARAMETERS AFTER LINK:
|
| Called during boot.
PutOval:
        LINK    A6,#-0x36                       | ALLOCATE LOCAL VARS

| OVALTOP .EQU 0 ;INTEGER
| OVALBOT .EQU OVALTOP+2 ;INTEGER
| OVALY .EQU OVALBOT+2 ;INTEGER
| RSQYSQ .EQU OVALY+2 ;LONGINT
| SQUARE .EQU RSQYSQ+4 ;64 BIT LONGFIX
| ODDNUM .EQU SQUARE+8 ;64 BIT LONGFIX
| ODDBUMP .EQU ODDNUM+8 ;64 BIT LONGFIX
| LEFTEDGE .EQU ODDBUMP+8 ;32 BIT FIXED POINT
| RIGHTEDGE .EQU LEFTEDGE+4 ;32 BIT FIXED POINT
| ONEHALF .EQU RIGHTEDGE+4 ;32 BIT FIXED POINT
| OVALSIZE .EQU ONEHALF+4 ;SIZE OF AN OVALREC
.set PARAMSIZE, 20                              | TOTAL SIZE OF PARAMETERS
.set DSTRECT, PARAMSIZE+8-4                     | ADDR OF RECT
.set OVALWIDTH, DSTRECT-2                       | INTEGER
.set OVALHEIGHT, OVALWIDTH-2                    | INTEGER
.set BUFHANDLE, OVALHEIGHT-4                    | LONG, HANDLE
.set INDEX, BUFHANDLE-4                         | LONG, VAR
.set SIZE, INDEX-4                              | LONG, VAR

| ------------------------------------------------
|
| A6 OFFSETS OF LOCAL VARIABLES AFTER LINK:
|
.set OVAL, -OVALSIZE                            | OVAL RECORD
.set SKIPTOP, OVAL-2                            | WORD
.set SKIPBOT, SKIPTOP-2                         | WORD
.set OLDLEFT, SKIPBOT-2                         | WORD
.set OLDRIGHT, OLDLEFT-2                        | WORD
.set VARSIZE, OLDRIGHT                          | SIZE OF LOCAL VARIABLES

        MOVEM.L D0-D7/A1-A5,-(SP)               | SAVE REGS

| ---------------------------------------------------------------
|
| INIT AN OVAL RECORD
|
        MOVE.L  0x18(A6),A0                     | POINT TO DSTRECT
        LEA.L   -0x2E(A6),A1                    | POINT TO OVAL RECORD
        MOVE    0x16(A6),D2                     | GET OVALWIDTH
        MOVE    0x14(A6),D1                     | GET OVALHEIGHT

| ---------------------------------------------------------------
|
        JSR     InitOval(PC)                    | INIT OVAL RECORD
        MOVE    -0xC(A6),-0x34(A6)              | OLDLEFT := LEFTEDGE
        MOVE    -0x8(A6),-0x36(A6)              | OLDRIGHT := RIGHTEDGE
        MOVE    0x14(A6),D0                     | GET OVALHEIGHT
        ASR     #1,D0                           | CALC OVAL HEIGHT DIV 2
        ADD     -0x2E(A6),D0                    | ADD OVAL TOP
        MOVE    D0,-0x30(A6)                    | SAVE SKIPTOP
        MOVE.L  0x18(A6),A0                     | POINT TO DSTRECT
        ADD     BOTTOM(A0),D0                   | ADD BOTTOM
        SUB     (A0),D0                         | SUBTRACT TOP
        SUB     0x14(A6),D0                     | SUBTRACT OVALHEIGHT
        MOVE    D0,-0x32(A6)                    | SAVE SKIPBOT

| -----------------------------------------------------------------
|
| GET BUF HANDLE, DE-REFERENCE IT, AND ADD INDEX
|
        MOVE.L  0x10(A6),A3                     | GET HANDLE

| -----------------------------------------------------------------
|
        MOVE.L  (A3),A3                         | DE-REFERENCE IT
        MOVE.L  A3,A2                           | REMEMBER BUFSTART FOR LATER
        MOVE.L  0xC(A6),A0                      | GET ADDR OF INDEX
        ADD     (A0),A3                         | ADD INDEX TO BUFPTR

| ----------------------------------------------------------
|
| BUFLIMIT := BUFSTART + BUFSIZE
|
        MOVE.L  A2,A1                           | GET BUFSTART
        MOVE.L  0x8(A6),A0                      | GET ADDR OF SIZE
        ADD     (A0),A1                         | LEAVE BUFLIMIT IN A1
        MOVE    -0x2E(A6),D6                    | D6 := OVAL TOP (VERT)

| ------------------------------------------------
|
| PUT THE TOP EDGE
|
        MOVE    -0x34(A6),D5                    | D5 := OLDLEFT

| ------------------------------------------------
|
        JSR     PUTPT(PC)                       | PUTPOINT (OLDLEFT,VERT)
        MOVE    -0x36(A6),D5                    | D5 := OLDRIGHT
        JSR     PUTPT(PC)                       | PUTPOINT (OLDRIGHT,VERT)

| -----------------------------------------------------
|
| FOR EACH VERTICAL, BUMP LEFTEDGE AND RIGHTEDGE.
| IF THEY DIFFER FROM OLDLEFT AND OLDRIGHT, PUT INVERSION
| POINTS FOR THE DIFFERENCES
|
| Called during boot.
NXTVERT:
        CMP     -0x30(A6),D6                    | IS VERT < SKIPTOP ?

| -----------------------------------------------------
|
| FOR EACH VERTICAL, BUMP LEFTEDGE AND RIGHTEDGE.
| IF THEY DIFFER FROM OLDLEFT AND OLDRIGHT, PUT INVERSION
| POINTS FOR THE DIFFERENCES
|
        BLT.B   PUTOVAL_YESBUMP                 | YES, BUMP OVAL RECORD
        CMP     -0x32(A6),D6                    | IS VERT >= SKIPBOT ?
        BLT.B   PUTOVAL_YESBUMP_SKIP            | NO, SKIP BUMPING
PUTOVAL_YESBUMP:
        MOVEM.L D6/A1-A3,-(SP)                  | YESBUMP: PRESERVE REGS
        LEA.L   -0x2E(A6),A3                    | POINT TO OVAL RECORD
        MOVE    D6,D0                           | GET CURRENT VERT
        JSR     BumpOval(PC)                    | BUMP IT TO NEXT SCANLINE
        MOVEM.L (SP)+,D6/A1-A3                  | RESTORE REGS
        MOVE    -0xC(A6),D5                     | D5 := NEW LEFTEDGE

| CHECK LEFT EDGE AND PUT TWO INVERSION POINTS IF IT HAS CHANGED
        CMP     -0x34(A6),D5                    | SAME AS OLDLEFT ?
        BEQ.B   PUTOVAL_YESBUMP_OK              | YES, CONTINUE
        JSR     PUTPT(PC)                       | PUTPOINT (NEWLEFT,VERT)
        MOVE    -0x34(A6),D5                    | D5 := OLDLEFT
        JSR     PUTPT(PC)                       | PUTPOINT(OLDLEFT,VERT)
        MOVE    -0xC(A6),-0x34(A6)              | UPDATE OLDLEFT
PUTOVAL_YESBUMP_OK:
        MOVE    -0x8(A6),D5                     | D5 := NEW RIGHTEDGE

| CHECK RIGHT EDGE AND PUT TWO INVERSION POINTS IF IT HAS CHANGED
        CMP     -0x36(A6),D5                    | SAME AS OLDRIGHT ?
        BEQ.B   PUTOVAL_YESBUMP_SKIP            | YES, CONTINUE
        JSR     PUTPT(PC)                       | PUTPOINT (NEWRIGHT,VERT)
        MOVE    -0x36(A6),D5                    | D5 := OLDRIGHT
        JSR     PUTPT(PC)                       | PUTPOINT(OLDRIGHT,VERT)
        MOVE    -0x8(A6),-0x36(A6)              | UPDATE OLDRIGHT
PUTOVAL_YESBUMP_SKIP:
        ADDQ.W  #0x1,D6                         | BUMP VERT
        CMP     -0x2C(A6),D6                    | IS VERT < OVAL BOTTOM ?
        BLT.B   NXTVERT                         | LOOP FOR ALL VERTICALS

| ------------------------------------------------
|
| PUT THE BOTTOM EDGE
|
        MOVE    -0x34(A6),D5                    | D5 := OLDLEFT

| ------------------------------------------------
|
        JSR     PUTPT(PC)                       | PUTPOINT (OLDLEFT,VERT)
        MOVE    -0x36(A6),D5                    | D5 := OLDRIGHT
        JSR     PUTPT(PC)                       | PUTPOINT (OLDRIGHT,VERT)

| ----------------------------------------------------
|
| UPDATE INDEX TO REFLECT POINTS ADDED, CLEAN UP STACK AND GO HOME.
|
        SUB.L   A2,A3                           | CALC BUFPTR-BUFSTART
        MOVE.L  0xC(A6),A0                      | GET VAR ADDR OF INDEX
        MOVE    A3,(A0)                         | UPDATE INDEX
        MOVEM.L (SP)+,D0-D7/A1-A5               | RESTORE REGISTERS
        UNLK    A6                              | RELEASE LOCAL VARS
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDA    #0x14,SP                        | STRIP 20 BYTES OF PARAMS
        JMP     (A0)                            | RETURN TO CALLER

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
PUTPT:
        CMP.L   A1,A3                           | IS BUFPTR < BUFLIMIT ?
        BLT.B   PUTOVAL_SIZEOK                  | YES, CONTINUE

| ---------------------------------------------------------------------
|
| BUFFER IS FULL, CALL STORAGE ALLOCATOR TO MAKE ROOM FOR 256 MORE POINTS.
| UPDATE BUFPTR, BUFSTART, BUFLIMIT, AND BUFSIZE AFTER RELOCATION.
|
        SUB.L   A2,A3                           | MAKE BUFPTR RELATIVE
        SUB.L   A2,A1                           | MAKE BUFLIMIT RELATIVE
        ADD     #1024,A1                        | MAKE BUFLIMIT BIGGER
        MOVEM.L D0-D7/A0-A3,-(SP)               | SAVE REGS
        MOVE.L  0x8(A6),A0                      | GET ADDR OF SIZE
        MOVE    A1,(A0)                         | UPDATE BUFFER SIZE
        MOVE.L  0x10(A6),-(SP)                  | PUSH HANDLE PARAM
        MOVE    A1,-(SP)                        | PUSH NEW SIZE
        JSR     SetHSize(PC)                    | MAKE THE BUFFER BIGGER
        MOVEM.L (SP)+,D0-D7/A0-A3               | RESTORE REGS
        MOVE.L  0x10(A6),A2                     | GET BUF HANDLE
        MOVE.L  (A2),A2                         | GET NEW BUFSTART
        ADD.L   A2,A3                           | MAKE BUFPTR UN-RELATIVE
        ADD.L   A2,A1                           | MAKE BUFLIMIT UN-RELATIVE

| -------------------------------------------------------------------
|
| ADD NEW POINT TO THE SAVE BUFFER UNLESS IT MATCHED THE PREVIOUS PT.
| DELETE DUPLICATE POINTS SINCE THEY WILL CANCEL EACH OTHER ANYWAY.
|
| Called during boot.
PUTOVAL_SIZEOK:
        CMP.L   A2,A3                           | SIZEOK: IS BUFPTR=STARTPTR ?
        BEQ.B   APPEND                          | BR IF FIRST POINT
        CMP     -0x2(A3),D5                     | DOES HORIZ MATCH PREV ?
        BNE.B   APPEND                          | NO, APPEND NEW POINT
        CMP     -0x4(A3),D6                     | DOES VERT MATCH PREV ?
        BNE.B   APPEND                          | NO, APPEND NEW POINT
        SUBQ.W  #0x4,A3                         | YES, DELETE DUPLICATE PAIR
        RTS                                     | return from PUTOVAL_SIZEOK

| ----------------------------------------------------------
|
| APPEND
|
| Called during boot.
APPEND:
        MOVE    D6,(A3)+                        | PUT VERT COORD
        MOVE    D5,(A3)+                        | PUT HORIZ COORD
        RTS                                     | return from APPEND



