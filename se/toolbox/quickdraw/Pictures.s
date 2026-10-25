| -----------------------------------------------------------
|
|
|     ****   ***   ***   *****  *   *  ****   *****   ***
|     *   *   *   *   *    *    *   *  *   *  *      *   *
|     *   *   *   *        *    *   *  *   *  *      *
|     ****    *   *        *    *   *  ****   ***     ***
|     *       *   *        *    *   *  * *    *          *
|     *       *   *   *    *    *   *  *  *   *      *   *
|     *      ***   ***     *     ***   *   *  *****   ***

| ------------------------------------------------------------------
|
| PROCEDURE StdComment(kind, dataSize: INTEGER; dataHandle: Handle);
|
| A6 offsets of params after LINK:
|   PARAMSIZE = 8
|   KIND       = PARAMSIZE+8-2  (WORD)
|   DATASIZE   = KIND-2         (WORD)
|   DATAHANDLE = DATASIZE-4     (LONG, Handle)
|
STDCOMMENT:
    LINK	A6,#0x0                                | no local vars
    MOVEM.L	D6-D7,-(A7)                         | save regs
    MOVEA.L	(A5),A0                             | point to QuickDraw globals
    MOVEA.L	(A0),A0                             | get current GrafPort
    TST.L	0x5C(A0)                              | are we saving for thePic ?
    BEQ.B	STDCOMMENT_DONE                       | no, quit
    MOVE.W	0xE(A6),D6                           | yes, get kind
    MOVE.W	0xC(A6),D7                           | is dataSize > 0 ?
    BGT.B	STDCOMMENT_OK                         | yes, use long format
|
| dataSize 0, use short format
|
    MOVEQ.L	#-0x60,D0                           | put short comment opcode (0xA0)
    JSR	DPUTPICBYTE(PC)                         | put short comment opcode
    MOVE.W	D6,-(A7)                             | push kind
    JSR	PUTPICWORD(PC)                          | put kind
    BRA.B	STDCOMMENT_DONE                       | go to end
| ----------------------------------------------------------
|
| STDCOMMENT_OK -- dataSize > 0, use long format
|
STDCOMMENT_OK:
    MOVEQ.L	#-0x5F,D0                           | put long comment opcode (0xA1)
    JSR	DPUTPICBYTE(PC)                         | put long comment opcode
    MOVE.W	D6,-(A7)                             | push kind
    JSR	PUTPICWORD(PC)                          | put kind
    MOVE.W	D7,-(A7)                             | push dataSize
    JSR	PUTPICWORD(PC)                          | put dataSize
    MOVEA.L	0x8(A6),A0                          | get data handle
    _HLock                                      | lock it
    MOVEA.L	0x8(A6),A0                          | get data handle
    MOVE.L	(A0),-(A7)                           | push DataPtr
    MOVE.W	D7,-(A7)                             | push ByteCount
    JSR	PUTPICDATA(PC)                          | put data to thePic
    MOVEA.L	0x8(A6),A0                          | get data handle
    _HUnlock                                    | unlock it
STDCOMMENT_DONE:
    MOVEM.L	(A7)+,D6-D7                         | restore regs
    UNLK	A6                                     | restore stack frame
    MOVEA.L	(A7)+,A0                            | get return address
    ADDQ.W	#0x8,A7                              | pop parameters
    JMP	(A0)                                    | tail-call return from STDCOMMENT_DONE via A0
| ------------------------------------------------------------------
|
| PROCEDURE StdGetPic(dataPtr: QDPtr; byteCount: INTEGER);
|
| Read byteCount bytes from the picture being played back into
| the buffer at dataPtr. Bumps PlayIndex by byteCount.
|
STDGETPIC:
    MOVEA.L	(A7)+,A0                            | pop return addr
    MOVE.W	(A7)+,D1                             | pop ByteCount
    MOVEA.L	(A7)+,A1                            | pop DataPtr
    MOVE.L	A0,-(A7)                             | push return addr
    MOVEA.L	(A5),A0                             | point to QuickDraw globals
    MOVE.L	-0xB4(A0),D0                         | get PlayIndex
    EXT.L	D1                                    | extend ByteCount to long
    ADD.L	D1,-0xB4(A0)                          | bump PlayIndex
    MOVEA.L	-0x9C(A0),A0                        | get play PicHandle
    MOVEA.L	(A0),A0                             | de-reference it
    ADDA.L	D0,A0                                | add PlayIndex
    BRA.B	STDGETPIC_START                       | go to loop start
| ----------------------------------------------------------
|
| NXTBYTE -- copy one src byte to dst
|
NXTBYTE:
    MOVE.B	(A0)+,(A1)+                          | copy one byte
STDGETPIC_START:
    DBF.W	D1,NXTBYTE                            | loop for all bytes
    RTS                                         | return from STDGETPIC_START
| ------------------------------------------------------------------
|
| PROCEDURE StdPutPic(dataPtr: QDPtr; byteCount: INTEGER);
|
| Append some picture bytes to a growing handle. Auto-grows by
| 256 bytes if PicMax is exceeded. On allocation failure, marks
| the picture dead (PicSize=-1, PicFrame=(0,0,0,0)).
|
| A6 offsets after LINK:
|   PARAMSIZE = 6
|   SRCPTR    = PARAMSIZE+8-4  (LONG)
|   BYTECOUNT = SRCPTR-2       (WORD)
|
STDPUTPIC:
    LINK	A6,#0x0                                | no locals
    MOVEM.L	D7/A3-A4,-(A7)                      | save regs
    MOVEA.L	(A5),A4                             | point to QuickDraw globals
    MOVEA.L	(A4),A4                             | get current GrafPort
    TST.L	0x5C(A4)                              | are we saving for a picture ?
    BEQ.B	STDPUTPIC_GOHOME                      | no, quit
    MOVEA.L	0x5C(A4),A4                         | yes, get PicSave handle
    MOVEA.L	(A4),A1                             | de-reference PicSave handle
    MOVE.L	0x8(A1),D7                           | get current size
    BEQ.B	STDPUTPIC_GOHOME                      | quit if picture is already dead
    MOVEA.L	(A1),A3                             | get thePic handle
    MOVE.W	0x8(A6),D0                           | get bytes requested
    EXT.L	D0                                    | make ByteCount long
    ADD.L	D7,D0                                 | calculate new size
    MOVE.L	D0,0x8(A1)                           | update PicIndex
    MOVEA.L	(A3),A0                             | de-reference thePic
    MOVE.W	D0,(A0)                              | PicSize := lo word of PicIndex
    CMP.L	0x4(A1),D0                            | is new size > PicMax ?
    BLE.B	STDPUTPIC_ERR                         | no, continue
    ADDI.L	#0x100,D0                            | grow pic in chunks
|
| Time to grow the picture in chunks of at least 256 bytes
|
    MOVE.L	D0,0x4(A1)                           | update new PicMax
    MOVEA.L	A3,A0                               | get thePic handle
    _SetHandleSize                              | make it bigger
    MOVEA.L	(A4),A1                             | re-deref PicSave handle
    BEQ.B	STDPUTPIC_ERR                         | continue if no error
|
| Failed to grow picture, so we will trim handle down to 10 bytes,
| clear PicIndex, and set PicSize to -1, PicFrame to (0,0,0,0).
|
    CLR.L	0x8(A1)                               | clear PicIndex as dead flag
    MOVEQ.L	#0xA,D0                             | ByteCount = 10
    MOVEA.L	A3,A0                               | get thePic handle
    _SetHandleSize                              | shrink picture to 10 bytes
    MOVEA.L	(A3),A0                             | de-reference PicHandle
    MOVE.W	#0xFFFF,(A0)+                        | stuff PicSize = -1
    CLR.L	(A0)+                                 | stuff PicFrame = (0,0,0,0)
    CLR.L	(A0)+                                 | all 8 bytes of PicFrame
    BRA.B	STDPUTPIC_GOHOME                      | and quit
| ----------------------------------------------------------
|
| STDPUTPIC_ERR -- copy data bytes into the picture
|
STDPUTPIC_ERR:
    MOVEA.L	(A1),A1                             | de-reference PicHandle
    MOVEA.L	(A1),A1                             | de-reference again
    ADDA.L	D7,A1                                | add OldSize for DstPtr
    MOVEA.L	0xA(A6),A0                          | get SrcPtr
    MOVE.W	0x8(A6),D0                           | get ByteCount
    BRA.B	STDPUTPIC_START                       | go to loop start
| ----------------------------------------------------------
|
| STDPUTPIC_NXTBYTE -- copy one src byte to dst
|
STDPUTPIC_NXTBYTE:
    MOVE.B	(A0)+,(A1)+                          | copy one byte
STDPUTPIC_START:
    DBF.W	D0,STDPUTPIC_NXTBYTE                  | loop for all bytes
STDPUTPIC_GOHOME:
    MOVEM.L	(A7)+,D7/A3-A4                      | restore regs
    UNLK	A6                                     | release stack frame
    MOVEA.L	(A7)+,A0                            | pop return address
    ADDQ.W	#0x6,A7                              | strip 6 bytes of params
    JMP	(A0)                                    | tail-call return from STDPUTPIC_GOHOME via A0
| ------------------------------------------------------------------
|
| PROCEDURE PicComment(kind, dataSize: INTEGER; dataHandle: Handle);
|
| Trap entry stub for StdComment with GrafProcs dispatch.
|
PICCOMMENT:
    MOVEA.L	(A5),A0                             | get global ptr
    MOVEA.L	(A0),A0                             | get thePort
    MOVE.L	0x68(A0),D0                          | is GrafProcs nil ?
    MOVEA.L	(0x11C4).W,A0                       | _StdComment (commentProc)
    BEQ.B	PICCOMMENT_USESTD                     | yes, use std proc
    MOVEA.L	D0,A0                               | put proc ptr in A0
    MOVEA.L	0x24(A0),A0                         | no, get proc ptr
PICCOMMENT_USESTD:
    JMP	(A0)                                    | tail-call to proc
| ------------------------------------------------------------------
|
| FUNCTION OpenPicture(picFrame: Rect): PicHandle;
|
| Opens a new picture for recording. Allocates the PicSave record
| and the picture handle (initial 256 bytes), seeds the picture
| header (size, frame, version opcode), copies the current pen/text
| state into the recording record, and stops drawing via HidePen.
|
OPENPICTURE:
    LINK	A6,#0x0                                | no locals
    MOVEM.L	A3-A4,-(A7)                         | save regs
    CLR.L	0xC(A6)                               | init fcn result to nil
    MOVEA.L	(A5),A4                             | point to QD globals
    MOVEA.L	(A4),A3                             | get current grafPort
    TST.L	0x5C(A3)                              | are we already saving ?
    BNE.W	OPENPICTURE_DONE                      | yes, return nil and quit
    JSR	HIDEPEN(PC)                             | no, turn off drawing
    MOVE.L	#0x1F4,D0                            | get byte count = 500
    _NewHandle                                  | allocate test handle
    BNE.W	OPENPICTURE_DONE                      | abort if heap < 500 bytes
    _DisposeHandle                              | discard test handle
    MOVEQ.L	#0x62,D0                            | byte count = 98 = sizeof(PicSave)
    _NewHandle                                  | allocate PicSave record
    MOVEA.L	A0,A4                               | get result handle
    MOVE.L	A4,0x5C(A3)                          | save in thePort.PicSave
    CLR.L	-(A7)                                 | make room for fcn result
    JSR	NEWRGN(PC)                              | allocate PicClipRgn
    MOVE.L	#0x100,D0                            | byte count = 256
    _NewHandle                                  | allocate the PicHandle
    MOVEA.L	A0,A1                               | get thePic handle
    MOVE.L	A1,0xC(A6)                           | put handle in fcn result
    MOVEA.L	(A4),A4                             | de-reference PicSave handle
    MOVE.L	A1,(A4)+                             | save PicHandle in thePic
    MOVEA.L	(A1),A1                             | de-reference PicHandle
    MOVE.W	#0xA,(A1)+                           | install picSize = 10
    MOVEA.L	0x8(A6),A0                          | point to picFrame param
    MOVE.L	(A0)+,(A1)+                          | copy rect into picture
    MOVE.L	(A0)+,(A1)+                          | (picFrame: 8 bytes)
    MOVE.L	#0x100,(A4)+                         | picMax := 256
    MOVE.L	#0xA,(A4)+                           | picIndex := 10
    MOVE.L	(A7)+,(A4)+                          | install picClipRgn
    CLR.L	(A4)+                                 | picBkPat := white
    CLR.L	(A4)+                                 | (8-byte pattern)
    CLR.L	(A4)+                                 | picTxFont = 0, picTxFace = []
    MOVE.W	#0x1,(A4)+                           | picTxMode := srcCopy
    CLR.W	(A4)+                                 | picTxSize := 0
    CLR.L	(A4)+                                 | picSpExtra := 0.0
    MOVE.L	#0x10001,D0                          | get (1,1)
    MOVE.L	D0,(A4)+                             | picTxNumer := (1,1)
    MOVE.L	D0,(A4)+                             | picTxDenom := (1,1)
    CLR.L	(A4)+                                 | picTxLoc := (0,0)
    CLR.L	(A4)+                                 | picPnLoc := (0,0)
    MOVE.L	D0,(A4)+                             | picPnSize := (1,1)
    MOVE.W	#0x8,(A4)+                           | picPnMode := patCopy
    MOVEQ.L	#-0x1,D0                            | get some black
    MOVE.L	D0,(A4)+                             | picPnPat := black
    MOVE.L	D0,(A4)+                             | (8-byte pattern)
    MOVE.L	D0,(A4)+                             | picFillPat := black
    MOVE.L	D0,(A4)+                             | (8-byte pattern)
    CLR.L	(A4)+                                 | picTheRect := (0,0,0,0)
    CLR.L	(A4)+                                 | (rect tail)
    CLR.L	(A4)+                                 | picOvSize := (0,0)
    MOVE.L	0x10(A3),(A4)+                       | picOrigin := current portRect.tl
    MOVE.L	#0x21,(A4)+                          | picFgColor := blackColor
    MOVE.L	#0x1E,(A4)+                          | picBkColor := whiteColor
    MOVE.W	#0x1101,-(A7)                        | version opcode + version 1
    JSR	PUTPICWORD(PC)                          | put version word to picture
OPENPICTURE_DONE:
    MOVEM.L	(A7)+,A3-A4                         | restore regs
    UNLK	A6                                     | release stack frame
    MOVE.L	(A7)+,(A7)                           | strip params, keep return addr
    RTS                                         | return from OpenPicture
| ------------------------------------------------------------------
|
| PROCEDURE ClosePicture;
|
| Closes the picture currently being recorded. Appends the endPic
| opcode (0xFF), trims the picture handle to its final size, and
| disposes of PicSave (clip rgn + record itself). TESetStyle_Apply restarts
| drawing.
|
CLOSEPICTURE:
    MOVEM.L	D6-D7/A3,-(A7)                      | save regs
    MOVEA.L	(A5),A3                             | point to QD globals
    MOVEA.L	(A3),A3                             | get current grafPort
    MOVE.L	0x5C(A3),D7                          | are we saving a picture ?
    BEQ.B	CLOSEPICTURE_GOHOME                   | no, oops, exit
    ST.B	-(A7)                                  | yes, push endPic opcode 0xFF
    JSR	PUTPICBYTE(PC)                          | put to thePic
    MOVEA.L	D7,A0                               | get handle to PicSave record
    MOVEA.L	(A0),A0                             | de-reference it
    MOVE.L	0xC(A0),D6                           | get picClipRgn
    MOVE.L	0x8(A0),D0                           | did picture overflow ?
    BEQ.B	CLOSEPIC_OVERFLO                      | yes, skip trim
    MOVEA.L	(A0),A0                             | de-reference handle
    _SetHandleSize                              | trim to final size
CLOSEPIC_OVERFLO:
    MOVEA.L	D6,A0                               | get picClipRgn
    _DisposeHandle                              | discard picClipRgn
    MOVEA.L	D7,A0                               | get PicSave handle
    _DisposeHandle                              | discard PicSave
    CLR.L	0x5C(A3)                              | reset PicSave to nil
    JSR	SHOWPEN(PC)                             | restore drawing
CLOSEPICTURE_GOHOME:
    MOVEM.L	(A7)+,D6-D7/A3                      | restore regs
    RTS                                         | return from ClosePicture
| ------------------------------------------------------------------
|
| PROCEDURE KillPicture(myPicture: PicHandle);
|
| Disposes of a picture handle.
|
KILLPICTURE:
    MOVEA.L	(A7)+,A1                            | pop return addr
    MOVEA.L	(A7)+,A0                            | pop handle
    _DisposeHandle                              | discard pic handle
    JMP	(A1)                                    | and return
| ------------------------------------------------------------------
|
| PROCEDURE DrawPicture(myPicture: PicHandle; dstRect: Rect);
|
| Plays back a picture into the current grafPort. Sets up scale
| numerator/denominator from dstRect/picFrame, snapshots the current
| grafPort to a SAVEPORT local, installs a fresh PicPlayRec + a
| temp clipRgn, then loops PicItem until endPic. Restores grafPort
| state and disposes temps on exit.
|
DRAWPICTURE:
    LINK	A6,#-0xA0                              | allocate locals
    MOVEM.L	D3-D7/A2-A4,-(A7)                   | save registers
    MOVEA.L	(A5),A4                             | point to QD globals
    MOVEA.L	(A4),A3                             | get current grafPort
    TST.L	0xC(A6)                               | is PicHandle nil ?
    BEQ.W	DRAWPICTURE_GOHOME                    | yes, quit
    MOVEA.L	0x8(A6),A0                          | point to dstRect
    MOVE.W	0x6(A0),D0                           | get right coord
    SUB.W	0x2(A0),D0                            | calc dst width
    BLE.W	DRAWPICTURE_GOHOME                    | quit if width <= 0
    MOVE.W	D0,-0xE(A6)                          | numer.h := dst width
    MOVE.W	0x4(A0),D0                           | get bottom coord
    SUB.W	(A0),D0                               | calc dst height
    BLE.W	DRAWPICTURE_GOHOME                    | quit if height <= 0
    MOVE.W	D0,-0x10(A6)                         | numer.v := dst height
    LEA.L	-0x18(A6),A1                          | point to local rect
    MOVE.L	(A0)+,(A1)+                          | copy data
    MOVE.L	(A0)+,(A1)+                          | toRect := dstRect
    MOVEA.L	0xC(A6),A0                          | get PicHandle
    MOVEA.L	(A0),A0                             | de-reference it
    LEA.L	0x2(A0),A0                            | point to picture frame
    MOVE.W	0x6(A0),D0                           | get right coord
    SUB.W	0x2(A0),D0                            | calc src width
    BLE.W	DRAWPICTURE_GOHOME                    | quit if width <= 0
    MOVE.W	D0,-0xA(A6)                          | denom.h := src width
    MOVE.W	0x4(A0),D0                           | get bottom coord
    SUB.W	(A0),D0                               | calc src height
    BLE.W	DRAWPICTURE_GOHOME                    | quit if height <= 0
    MOVE.W	D0,-0xC(A6)                          | denom.v := src height
    LEA.L	-0x20(A6),A1                          | point to fromRect
    MOVE.L	(A0)+,(A1)+                          | copy data
    MOVE.L	(A0)+,(A1)+                          | fromRect := picFrame
    MOVEA.L	A3,A0                               | src = thePort
    LEA.L	-0xA0(A6),A1                          | dst = SAVEPORT
    MOVEQ.L	#0x35,D0                            | put opcode in D0
DRAWPICTURE_LOOP:
    MOVE.W	(A0)+,(A1)+                          | copy a word
    DBF.W	D0,DRAWPICTURE_LOOP                   | loop entire port
    CLR.L	-0xA8(A4)                             | patAlign := (0,0)
    MOVE.L	0xC(A6),-0x9C(A4)                    | save picture for StdGetPic
    MOVE.L	#0xA,-0xB4(A4)                       | init index to first opcode
    LEA.L	-0x34(A6),A0                          | point to local buffer
    CLR.L	(A0)+                                 | theRect := (0,0,0,0)
    CLR.L	(A0)+                                 | (rect tail)
    CLR.L	(A0)+                                 | penLoc := (0,0)
    CLR.L	(A0)+                                 | textLoc := (0,0)
    CLR.L	(A0)+                                 | ovalSize := (0,0)
    MOVE.L	0x1C(A3),-0x4(A6)                    | save user clipRgn
    CLR.L	-(A7)                                 | make room for fcn result
    JSR	NEWRGN(PC)                              | allocate a new region
    MOVE.L	(A7)+,-0x8(A6)                       | install theClip
    CLR.L	-(A7)                                 | make room for fcn result
    JSR	NEWRGN(PC)                              | allocate a new region
    MOVE.L	(A7)+,0x1C(A3)                       | allocate temp clipRgn
    LEA.L	0x20(A3),A0                           | point to bkPat
    CLR.L	(A0)+                                 | bkPat := white
    CLR.L	(A0)+                                 | (8-byte pattern)
    MOVEQ.L	#-0x1,D0                            | get some black
    MOVE.L	D0,(A0)+                             | fillPat := black
    MOVE.L	D0,(A0)+                             | (8-byte pattern)
    CLR.L	(A0)+                                 | pnLoc := (0,0)
    MOVE.L	#0x10001,D1                          | get (1,1)
    MOVE.L	D1,(A0)+                             | pnSize := (1,1)
    MOVE.W	#0x8,(A0)+                           | pnMode := patCopy
    MOVE.L	D0,(A0)+                             | pnPat := black
    MOVE.L	D0,(A0)+                             | (8-byte pattern)
    ADDQ.W	#0x2,A0                              | skip over pnVis
    CLR.L	(A0)+                                 | txFont, txFace := 0
    MOVE.W	#0x1,(A0)+                           | txMode := srcOr
    CLR.W	(A0)+                                 | txSize := 0
    CLR.L	(A0)+                                 | spExtra := 0.0
    MOVE.L	#0x21,(A0)+                          | fgColor := blackColor
    MOVE.L	#0x1E,(A0)+                          | bkColor := whiteColor
| LEAVE COLRBIT ALONE
| LEAVE PATSTRETCH ALONE
| LEAVE PICSAVE ALONE
| LEAVE RGNSAVE ALONE
| LEAVE POLYSAVE ALONE
| LEAVE GRAFPROCS ALONE

| ---------------------------------------------------
|
| NOW DRAW THE PICTURE:
| REPEAT UNTIL NOT PicItem(playState);
|
| ---------------------------------------------------
|
| NOW DRAW THE PICTURE:
| REPEAT UNTIL NOT PicItem(playState);
|
MORE:
    CLR.B	-(A7)                                 | make room for fcn result
    PEA.L	-0x34(A6)                             | push addr of playState
    JSR	PICITEM(PC)                             | draw one picture item
    MOVE.B	(A7)+,D0                             | pop boolean result
    BNE.B	MORE                                  | loop till false
    MOVEA.L	-0x8(A6),A0                         | get region handle
    _DisposeHandle                              | discard temp region
    MOVEA.L	0x1C(A3),A0                         | get tempClip
    _DisposeHandle                              | discard tempClip
    LEA.L	-0xA0(A6),A0                          | src = SAVEPORT
    MOVEQ.L	#0x35,D0                            | put opcode in D0
MORE_LOOP:
    MOVE.W	(A0)+,(A3)+                          | copy a word
    DBF.W	D0,MORE_LOOP                          | loop entire port
    CLR.L	-0xA8(A4)                             | restore patAlign to (0,0)
    CLR.L	-0x9C(A4)                             | set playPic to nil
    CLR.L	-0xB4(A4)                             | and playIndex to 0
| Called by: DRAWPICTURE
DRAWPICTURE_GOHOME:
    MOVEM.L	(A7)+,D3-D7/A2-A4                   | restore registers
    UNLK	A6                                     | release stack frame
    MOVEA.L	(A7)+,A0                            | get return address
    ADDQ.W	#0x8,A7                              | pop parameters
    JMP	(A0)                                    | tail-call return from DRAWPICTURE_GOHOME via A0
| ------------------------------------------------------------------
|
| FUNCTION PicItem(VAR playState: PicPlayRec): BOOLEAN;
|
| Draws one picture item, updating playState and thePort.
| Returns FALSE when an endPic opCode is encountered.
| The only state modified other than thePort and playState is
| patAlign.
|
PICITEM:
    LINK	A6,#-0x138                             | allocate locals
    MOVEM.L	D3-D7/A2-A4,-(A7)                   | save registers
    MOVE.L	A7,-0x138(A6)                        | remember stack for abort
    MOVEA.L	(A5),A4                             | point to QD globals
    MOVEA.L	(A4),A3                             | get current grafPort
    BSR.W	GETUBYTE                              | get opcode byte
    MOVE.W	D0,D7                                | put it in D7
    CMPI.B	#0xFF,D7                             | is this the picEnd opcode ?
    BNE.B	NOTEND                                | no, continue
    CLR.B	0xC(A6)                               | yes, return FALSE
    BRA.W	KILL1_EXIT                            | and quit
| ----------------------------------------------------------
|
| NOTEND -- handle a non-endPic opcode
|
| Param opcodes ($00..$1F) just set state in thePort, with no
| drawing. Drawing opcodes ($20..$FE) split into noun (high nibble)
| and verb (low nibble + bit 3 = sameFlag).
|
NOTEND:
    MOVE.B	#0x1,0xC(A6)                         | return TRUE
    CMPI.W	#0x20,D7                             | is it a param opcode ?
    BCS.B	NOTEND_OK                             | yes, go to it
| Drawing opcode: split into noun (hi nibble) + verb (lo nibble) +
| sameFlag (bit 3).
    MOVE.B	D7,D0                                | copy opcode
    ANDI.W	#0xF0,D0                             | mask for hi nibble
    BTST	#0x3,D7                                | is opcode bit 3 set ?
    SNE.B	-0x28(A6)                             | remember in sameFlag
    ANDI.W	#0x7,D7                              | get verb from lo nibble
    LSR.W	#0x3,D0                               | double hi nibble for index
    MOVE.W	DRAWVERB_TBL(PC,D0.W),D0             | get jump offset
    JMP	DRAWVERB_TBL(PC,D0.W)                   | take case jump
| Drawing-opcode noun-dispatch table: 17 word offsets relative to
| DRAWVERB_TBL, indexed by (opcode>>4)*2. Out-of-range nouns route
| to KILL1 (offset 0x061A) which discards Handle1 and returns TRUE.
DRAWVERB_TBL:
    .long	0x061A061A                            | nouns 0,1: invalid
    .long	0x01C202C8                            | nouns 2,3: line, rect
    .long	0x02E20304                            | nouns 4,5: roundRect, oval
    .long	0x031E0344                            | nouns 6,7: arc, region
    .long	0x037603A8                            | nouns 8,9: text, bits
    .long	0x047E061A                            | nouns A,B: comment, killN
    .long	0x061A061A                            | nouns C,D: invalid
    .long	0x061A061A                            | nouns E,F: invalid
    .short	0x061A                               | (extra slot to KILL1)
| NOTEND_OK -- handle a state-setting param opcode ($00..$1F)

NOTEND_OK:
    ANDI.W	#0x1F,D7                             | mask out param opcode
| Opcodes $00..$1F do no drawing, they just set parameters.
    ADD.W	D7,D7                                 | double param for case index
    MOVE.W	PARAMOP_TBL(PC,D7.W),D0              | get case jump offset
    JMP	PARAMOP_TBL(PC,D0.W)                    | take case jump
| Param-opcode dispatch table: 32 word offsets relative to
| PARAMOP_TBL, indexed by opcode*2. Most slots above $11 route
| to KILL1 (offset 0x05EA) since param opcodes $12..$1F are
| reserved.
PARAMOP_TBL:
    .long	0x05EA0040                            | $00 noOp, $01 clipRgn
    .long	0x009E00A4                            | $02 bkPat, $03 txFont
    .long	0x00AA00B4                            | $04 txFace, $05 txMode
    .long	0x00C000C6                            | $06 spExtra, $07 pnSize
    .long	0x0126012E                            | $08 pnMode, $09 pnPat
    .long	0x0136013E                            | $0A fillPat, $0B ovSize
    .long	0x015E00BA                            | $0C origin, $0D txSize
    .long	0x00920098                            | $0E fgColor, $0F bkColor
    .long	0x00E6011E                            | $10 txRatio, $11 picVersion
    .long	0x05EA05EA                            | $12,$13 reserved
    .long	0x05EA05EA                            | $14,$15 reserved
    .long	0x05EA05EA                            | $16,$17 reserved
    .long	0x05EA05EA                            | $18,$19 reserved
    .long	0x05EA05EA                            | $1A,$1B reserved
    .long	0x05EA05EA                            | $1C,$1D reserved
    .long	0x05EA05EA                            | $1E,$1F reserved
| NOTEND_CONT_3 -- $01 clipRgn opcode handler
NOTEND_CONT_3:
    BSR.W	GETHNDL                               | copy rgn into HANDLE1
    MOVEA.L	0x8(A6),A2                          | point to playState record
    MOVE.L	-0x4(A6),-(A7)                       | push HANDLE1
    MOVE.L	0x2C(A2),-(A7)                       | push playState theClip
XCLIP2:
    JSR	COPYRGN(PC)                             | copy HANDLE1 into theClip
    MOVEA.L	0x8(A6),A2                          | point to playState record
    MOVE.L	-0x4(A6),-(A7)                       | push HANDLE1 temp
    PEA.L	0x14(A2)                              | push fromRect
    PEA.L	0x1C(A2)                              | push toRect
    JSR	MAPRGN(PC)                              | map rgn into dst coords
    MOVEA.L	0x8(A6),A2                          | point to playState record
    MOVE.L	-0x4(A6),-(A7)                       | push mapped rgn
    MOVE.L	0x30(A2),-(A7)                       | push original userClip
    MOVE.L	0x1C(A3),-(A7)                       | push dst = thePort.clipRgn
    JSR	SECTRGN(PC)                             | put intersect into clipRgn
    BRA.W	KILL1                                 | discard HANDLE1 and quit
| GET8 / GET4 / GET2 -- common N-byte fetch helpers (count in D6
| then fall through to GETDONE which copies count bytes from the
| picture stream into the addr in A3).
GET8:
    MOVEQ.L	#0x8,D6                             | byteCount = 8
    BRA.W	GETDONE                               | copy 8 bytes and quit
GET4:
    MOVEQ.L	#0x4,D6                             | byteCount = 4
    BRA.W	GETDONE                               | copy 4 bytes and quit
GET2:
    MOVEQ.L	#0x2,D6                             | byteCount = 2
    BRA.W	GETDONE                               | copy 2 bytes and quit
| GET2_CONT -- $0E fgColor opcode handler
GET2_CONT:
    LEA.L	0x50(A3),A3                           | point to fgColor
    BRA.B	GET4                                  | get foreground color
| GET2_CONT_2 -- $0F bkColor opcode handler
GET2_CONT_2:
    LEA.L	0x54(A3),A3                           | point to bkColor
    BRA.B	GET4                                  | get background color
| GET2_CONT_3 -- $02 bkPat opcode handler
GET2_CONT_3:
    LEA.L	0x20(A3),A3                           | point to bkPat
    BRA.B	GET8                                  | get bkPat
| GET2_CONT_4 -- $03 txFont opcode handler
GET2_CONT_4:
    LEA.L	0x44(A3),A3                           | point to txFont
    BRA.B	GET2                                  | get txFont
| GET2_CONT_5 -- $04 txFace opcode handler
GET2_CONT_5:
    LEA.L	0x46(A3),A3                           | point to txFace
    MOVEQ.L	#0x1,D6                             | size is 1 byte
    BRA.W	GETDONE                               | get txFace
| GET2_CONT_6 -- $05 txMode opcode handler
GET2_CONT_6:
    LEA.L	0x48(A3),A3                           | point to txMode
    BRA.B	GET2                                  | get txMode
| GET2_CONT_7 -- $0D txSize opcode handler
GET2_CONT_7:
    LEA.L	0x4A(A3),A3                           | point to txSize
    BRA.B	GET2                                  | get txSize
| GET2_CONT_8 -- $06 spExtra opcode handler
GET2_CONT_8:
    LEA.L	0x4C(A3),A3                           | point to spExtra
    BRA.B	GET4                                  | get fixed-point space extra
| GET2_CONT_9 -- $07 pnSize opcode handler (scale on read)
GET2_CONT_9:
    JSR	GETLONG(PC)                             | get pnSize
    MOVE.L	D0,0x34(A3)                          | install into thePort
    PEA.L	0x34(A3)                              | push pen size
    MOVEA.L	0x8(A6),A2                          | point to playState record
    PEA.L	0x14(A2)                              | push source rect
    PEA.L	0x1C(A2)                              | push dest rect
    JSR	SCALEPT(PC)                             | scale pnSize
    BRA.W	KILL1_EXIT                            | go to common exit
| GET2_CONT_10 -- $10 txRatio opcode handler (numer/denom)
GET2_CONT_10:
    MOVEA.L	0x8(A6),A3                          | point to playState record
    JSR	GETLONG(PC)                             | get text numer
    MOVE.L	D0,0x24(A3)                          | install into playState
    JSR	GETLONG(PC)                             | get text denom
    MOVE.L	D0,0x28(A3)                          | install into playState
    PEA.L	0x24(A3)                              | push numer
    PEA.L	0x28(A3)                              | push denom
    PEA.L	0x14(A3)                              | push fromRect
    JSR	MAPRATIO(PC)                            | adjust txRatio for rect mapping
    PEA.L	0x24(A3)                              | push numer (now mapped)
    PEA.L	0x14(A3)                              | push fromRect
    PEA.L	0x1C(A3)                              | push toRect
    JSR	SCALEPT(PC)                             | scale numer
    BRA.W	KILL1_EXIT                            | go to common exit
| GET2_CONT_11 -- $11 picVersion opcode handler
GET2_CONT_11:
    BSR.W	GETUBYTE                              | get version number byte
    BRA.W	KILL1_EXIT                            | and ignore it
| GET2_CONT_12 -- $08 pnMode opcode handler
GET2_CONT_12:
    LEA.L	0x38(A3),A3                           | point to pnMode
    BRA.W	GET2                                  | get pnMode
| GET2_CONT_13 -- $09 pnPat opcode handler
GET2_CONT_13:
    LEA.L	0x3A(A3),A3                           | point to pnPat
    BRA.W	GET8                                  | get pnPat
| GET2_CONT_14 -- $0A fillPat opcode handler
GET2_CONT_14:
    LEA.L	0x28(A3),A3                           | point to fillPat
    BRA.W	GET8                                  | get fillPat
| GET2_CONT_15 -- $0B ovSize opcode handler (scale on read)
GET2_CONT_15:
    JSR	GETLONG(PC)                             | get oval size
    MOVEA.L	0x8(A6),A2                          | point to playState record
    MOVE.L	D0,0x10(A2)                          | save new point
    PEA.L	0x10(A2)                              | push new point
    PEA.L	0x14(A2)                              | push fromRect
    PEA.L	0x1C(A2)                              | push toRect
    JSR	SCALEPT(PC)                             | scale ovalSize
    BRA.W	KILL1_EXIT                            | go to common exit
| -----------------------------------------------------
|
| GET2_CONT_16 -- $0C origin opcode handler
| Change origin: add dh and dv to fromRect, adjust patAlign,
| then re-map theClip via XCLIP2.
|
GET2_CONT_16:
    JSR	GETLONG(PC)                             | get dh,dv
    MOVEA.L	0x8(A6),A2                          | point to playState record
    ADD.W	D0,0x14(A2)                           | add dv to fromRect
    ADD.W	D0,0x18(A2)                           | adjust rect bottom
    ADD.W	D0,-0xA8(A4)                          | and to patAlign
    SWAP.W	D0                                   | get dh in lo word
    ADD.W	D0,0x16(A2)                           | add dh to fromRect
    ADD.W	D0,0x1A(A2)                           | adjust rect right
    ADD.W	D0,-0xA6(A4)                          | and to patAlign
    MOVE.L	0x2C(A2),-(A7)                       | push theClip
    CLR.L	-(A7)                                 | room for fcn result
    JSR	NEWRGN(PC)                              | allocate a temp rgn
    MOVE.L	(A7),-0x4(A6)                        | put in HANDLE1
    BRA.W	XCLIP2                                | copy, map, sectScan, discard
| ---------------------------------------------------
|
| TEXT OR LINE OPCODES:
|
| LINE: 20, PNLOC(pt), NEWPT(pt)
| LINEFROM: 21, NEWPT(pt)
| SHORT LINE: 22, PNLOC(pt), DH(byte), DV(byte)
| SHORTLNFROM: 23, DH(byte), DV(byte)
|
| TEXT: 28,29,2A,2B
|
| ---------------------------------------------------
|
| GET2_CONT_17 -- noun = line/text (opcodes $20..$2B)
|
| LINE: $20, pnLoc(pt), newPt(pt)
| LINEFROM: $21, newPt(pt)
| SHORT LINE: $22, pnLoc(pt), dh(byte), dv(byte)
| SHORTLNFROM: $23, dh(byte), dv(byte)
|
| TEXT: $28..$2B (long, dh, dv, dhdv)
|
GET2_CONT_17:
    TST.B	-0x28(A6)                             | is this a text opcode ?
    BNE.W	TEXTOP                                | yes, do it
    MOVEA.L	0x8(A6),A2                          | point to playState record
    MOVE.L	0x8(A2),D0                           | no, get previous line endpoint
    ROR.W	#0x1,D7                               | is lo nibble odd ? (bit 0)
    BCS.B	LNFROM                                | yes, draw lineFrom prev
    BSR.W	GETLONG                               | no, get new startPt
LNFROM:
    MOVE.L	D0,0x30(A3)                          | copy startPt into thePort.pnLoc
    MOVE.L	D0,-0x2C(A6)                         | save for short dh,dv below
    MOVEA.L	0x8(A6),A2                          | point to playState record
    PEA.L	0x30(A3)                              | push pen location
    PEA.L	0x14(A2)                              | push fromRect
    PEA.L	0x1C(A2)                              | push toRect
    JSR	MAPPT(PC)                               | map startPt
    ROR.W	#0x1,D7                               | is opcode bit 1 set ?
    BCS.B	SHORTLN                               | yes, use short dh,dv form
    BSR.W	GETLONG                               | no, get newPt
    MOVE.L	D0,-0x2C(A6)                         | put in temp
    BRA.B	LNOK                                  | and continue
| SHORTLN -- short-form line: read signed dh,dv bytes
SHORTLN:
    BSR.W	GETSBYTE                              | get a signed byte (dv)
    ADD.W	D0,-0x2A(A6)                          | add to startPt.h
    BSR.W	GETSBYTE                              | get a signed byte (dh)
    ADD.W	D0,-0x2C(A6)                          | add to startPt.v
LNOK:
    MOVEA.L	0x8(A6),A2                          | point to playState record
    MOVE.L	-0x2C(A6),0x8(A2)                    | remember newPt for next time
    PEA.L	-0x2C(A6)                             | push address of newPt
    PEA.L	0x14(A2)                              | push fromRect
    PEA.L	0x1C(A2)                              | push toRect
    JSR	MAPPT(PC)                               | map newPt
    MOVE.L	-0x2C(A6),-(A7)                      | push newPt param for lineProc
    MOVEA.L	(0x1040).W,A0                       | _StdLine (lineProc)
    MOVE.L	0x68(A3),D0                          | is grafProcs nil ?
    BEQ.B	LNOK_OK                               | yes, use std proc
    MOVEA.L	D0,A0                               | copy pointer
    MOVEA.L	0x4(A0),A0                          | no, get procPtr
LNOK_OK:
    BRA.W	CALL0                                 | call no-argument routine
| TEXTOP -- noun = text, verb selects format:
| LONG TEXT: $28, txLoc(pt), count(0..255), text
| DH TEXT: $29, dh(0..255), count(0..255), text
| DV TEXT: $2A, dv(0..255), count(0..255), text
| DHDV TEXT: $2B, dh(0..255), dv(0..255), count(0..255), text
TEXTOP:
    ANDI.W	#0x3,D7                              | mask to 2 bits
    BEQ.B	LONGTXT                               | $28 long text format
    ROR.W	#0x1,D7                               | do we need dh ? (bit 0)
    BCC.B	PICITEM_DHOK                          | no, continue
    BSR.W	GETUBYTE                              | get dh 0..255
    MOVEA.L	0x8(A6),A2                          | point to playState record
    ADD.W	D0,0xE(A2)                            | bump textLoc.h
PICITEM_DHOK:
    ROR.W	#0x1,D7                               | dhOk: do we need dv ? (bit 1)
    BCC.B	TEXTOP2                               | no, continue
    BSR.W	GETUBYTE                              | get dv 0..255
    MOVEA.L	0x8(A6),A2                          | point to playState record
    ADD.W	D0,0xC(A2)                            | bump textLoc.v
    BRA.B	TEXTOP2                               | share code
| LONGTXT -- $28 absolute textLoc form
LONGTXT:
    BSR.W	GETLONG                               | get txLoc, unmapped
    MOVEA.L	0x8(A6),A2                          | point to playState record
    MOVE.L	D0,0xC(A2)                           | save in textLoc
TEXTOP2:
    BSR.W	GETUBYTE                              | get text length 0..255
    MOVE.W	D0,D6                                | save length in D6
    PEA.L	-0x12C(A6)                            | push addr of text buf
    MOVE.W	D6,-(A7)                             | push byteCount
    JSR	GETPICDATA(PC)                          | get the text
    MOVEA.L	0x8(A6),A2                          | point to playState record
    MOVE.L	0xC(A2),0x30(A3)                     | copy textLoc into pnLoc
    PEA.L	0x30(A3)                              | push pen location
    PEA.L	0x14(A2)                              | push fromRect
    PEA.L	0x1C(A2)                              | push toRect
    JSR	MAPPT(PC)                               | map pnLoc
    MOVE.W	D6,-(A7)                             | push character count
    PEA.L	-0x12C(A6)                            | push address of text
    MOVEA.L	0x8(A6),A2                          | point to playState record
    MOVE.L	0x24(A2),-(A7)                       | push numer
    MOVE.L	0x28(A2),-(A7)                       | push denom
    MOVEA.L	(0x1008).W,A0                       | _StdText (textProc)
    MOVE.L	0x68(A3),D0                          | is grafProcs nil ?
    BEQ.B	TEXTOP2_OK                            | yes, use std proc
    MOVEA.L	D0,A0                               | copy pointer
    MOVEA.L	(A0),A0                             | dereference handle
TEXTOP2_OK:
    BRA.W	CALL0                                 | call no-argument routine
| ---------------------------------------------------
|
| Rect: OP, RECT
|
RECTOP:
    MOVE.B	D7,-(A7)                             | push verb
    BSR.W	GETRECT                               | get and push dstRect
    MOVEA.L	(0x1080).W,A0                       | _StdRect (rectProc)
    MOVE.L	0x68(A3),D0                          | is grafProcs nil ?
    BEQ.B	RECTOP_OK                             | yes, use std proc
    MOVEA.L	D0,A0                               | copy pointer
    MOVEA.L	0x8(A0),A0                          | no, get procPtr
RECTOP_OK:
    BRA.W	CALL0                                 | call no-argument routine
| ---------------------------------------------------
|
| RRect: OP, RECT, OVALPT
|
RRECTOP:
    MOVE.B	D7,-(A7)                             | push verb
    BSR.W	GETRECT                               | get and push dstRect
    MOVEA.L	0x8(A6),A2                          | point to playState record
    MOVE.L	0x10(A2),-(A7)                       | push ovHt,ovWd
    MOVEA.L	(0x10BC).W,A0                       | _StdRRect (rRectProc)
    MOVE.L	0x68(A3),D0                          | is grafProcs nil ?
    BEQ.B	RRECTOP_OK                            | yes, use std proc
    MOVEA.L	D0,A0                               | copy pointer
    MOVEA.L	0xC(A0),A0                          | no, get procPtr
RRECTOP_OK:
    BRA.W	CALL0                                 | call no-argument routine
| ---------------------------------------------------
|
| Oval: OP, RECT
|
OVALOP:
    MOVE.B	D7,-(A7)                             | push verb
    BSR.W	GETRECT                               | get and push dstRect
    MOVEA.L	(0x10D8).W,A0                       | _StdOval (ovalProc)
    MOVE.L	0x68(A3),D0                          | is grafProcs nil ?
    BEQ.B	OVALOP_OK                             | yes, use std proc
    MOVEA.L	D0,A0                               | copy pointer
    MOVEA.L	0x10(A0),A0                         | no, get procPtr
OVALOP_OK:
    BRA.W	CALL0                                 | call no-argument routine
| ---------------------------------------------------
|
| Arc: OP, RECT, STARTANGLE, ARCANGLE
|
ARCOP:
    MOVE.B	D7,-(A7)                             | push verb
    BSR.W	GETRECT                               | get and push dstRect
    BSR.W	GETWORD                               | get startAngle
    MOVE.W	D0,-(A7)                             | push startAngle
    BSR.W	GETWORD                               | get arcAngle
    MOVE.W	D0,-(A7)                             | push arcAngle
    MOVEA.L	(0x10F4).W,A0                       | _StdArc (arcProc)
    MOVE.L	0x68(A3),D0                          | is grafProcs nil ?
    BEQ.B	ARCOP_OK                              | yes, use std proc
    MOVEA.L	D0,A0                               | copy pointer
    MOVEA.L	0x14(A0),A0                         | no, get procPtr
ARCOP_OK:
    BRA.W	CALL0                                 | call no-argument routine
| ---------------------------------------------------
|
| Poly: OP, POLY
|
POLY:
    BSR.W	GETHNDL                               | copy poly into HANDLE1
    MOVE.L	-0x4(A6),-(A7)                       | push polyHandle
    MOVEA.L	0x8(A6),A2                          | point to playState record
    PEA.L	0x14(A2)                              | push fromRect
    PEA.L	0x1C(A2)                              | push toRect
    JSR	MAPPOLY(PC)                             | map poly into dst coords
    MOVE.B	D7,-(A7)                             | push verb
    MOVE.L	-0x4(A6),-(A7)                       | push polyHandle
    MOVEA.L	(0x1114).W,A0                       | _StdPoly (polyProc)
    MOVE.L	0x68(A3),D0                          | is grafProcs nil ?
    BEQ.B	POLY_OK                               | yes, use std proc
    MOVEA.L	D0,A0                               | copy pointer
    MOVEA.L	0x18(A0),A0                         | no, get procPtr
POLY_OK:
    BRA.W	CALL1                                 | call one-argument routine
| ---------------------------------------------------
|
| Rgn: OP, RGN
|
PICRGNOP:
    BSR.W	GETHNDL                               | copy rgn into HANDLE1
    MOVE.L	-0x4(A6),-(A7)                       | push rgnHandle
    MOVEA.L	0x8(A6),A2                          | point to playState record
    PEA.L	0x14(A2)                              | push fromRect
    PEA.L	0x1C(A2)                              | push toRect
    JSR	MAPRGN(PC)                              | map rgn into dst coords
    MOVE.B	D7,-(A7)                             | push verb
    MOVE.L	-0x4(A6),-(A7)                       | push rgnHandle
    MOVEA.L	(0x1144).W,A0                       | _StdRgn (rgnProc)
    MOVE.L	0x68(A3),D0                          | is grafProcs nil ?
    BEQ.B	PICRGNOP_OK                           | yes, use std proc
    MOVEA.L	D0,A0                               | copy pointer
    MOVEA.L	0x1C(A0),A0                         | no, get procPtr
PICRGNOP_OK:
    BRA.W	CALL1                                 | call one-argument routine
| --------------------------------------------------------------------------
|
| BITSOP -- bitsRect / bitsRgn / packBitsRect / packBitsRgn opcodes
|
| BitsRect:    $90, rowBytes, bounds, srcRect, dstRect, mode, bitData
| BitsRgn:     $91, rowBytes, bounds, srcRect, dstRect, mode, maskRgn,
|                   bitData
| PackBitsRect:$98, rowBytes, bounds, srcRect, dstRect, mode, bitData
| PackBitsRgn: $99, rowBytes, bounds, srcRect, dstRect, mode, maskRgn,
|                   bitData (per-scanline RLE)
|
BITSOP:
    PEA.L	-0x22(A6)                             | push local rect (rowBytes,bounds,src,dst)
    MOVE.W	#0x1A,-(A7)                          | push byteCount = 26
    JSR	GETPICDATA(PC)                          | get rowBytes, bounds, src, dst
    MOVEA.L	0x8(A6),A2                          | point to playState record
    PEA.L	-0x10(A6)                             | push local point
    PEA.L	0x14(A2)                              | push fromRect
    PEA.L	0x1C(A2)                              | push toRect
    JSR	MAPRECT(PC)                             | map dstRect
    PEA.L	-0x26(A6)                             | push srcBits
    PEA.L	-0x18(A6)                             | push addr of srcRect
    PEA.L	-0x10(A6)                             | push addr of dstRect
    BSR.W	GETWORD                               | get mode
    MOVE.W	D0,-(A7)                             | push mode
    TST.W	D7                                    | is maskRgn used ?
    BNE.B	USERGN                                | yes, continue
    CLR.L	-(A7)                                 | no, push maskRgn = nil
    BRA.B	USERGN_CONT                           | and continue
| USERGN -- bitsRgn / packBitsRgn: read maskRgn into HANDLE1
USERGN:
    BSR.W	GETHNDL                               | get maskRgn into HANDLE1
    MOVE.L	-0x4(A6),-(A7)                       | push maskRgn
    MOVE.L	-0x4(A6),-0x8(A6)                    | remember maskRgn in HANDLE2
USERGN_CONT:
    MOVE.W	-0x1C(A6),D6                         | get bottom bound
    SUB.W	-0x20(A6),D6                          | calc height
    MOVE.W	D6,D5                                | copy height
    MULU.W	-0x22(A6),D5                         | calc bitmap byte size
    MOVE.L	D5,D0                                | get byteCount
    _NewHandle                                  | allocate bits handle
    BEQ.W	MEMOK                                 | continue if not memFull
    MOVEA.L	(A7)+,A0                            | pop maskRgn (maybe nil)
    _DisposeHandle                              | discard maskRgn
    BRA.W	KILL1_ERR                             | and abort
| MEMOK -- got the bits handle; HLock and read scanlines
MEMOK:
    _HLock                                      | lock HANDLE1
    MOVE.L	A0,-0x4(A6)                          | remember in HANDLE1
| If opcode bit 3 set, then unpack compressed scanlines.
    MOVEA.L	-0x4(A6),A0                         | get HANDLE1
    TST.B	-0x28(A6)                             | was bit 3 set ?
    BEQ.B	PICITEM_NOPACK                        | no, it's not packed
    MOVE.L	(A0),-0x134(A6)                      | yes, init dstPtr
    BRA.B	PICITEM_START1                        | go to loop start
| PICITEM_MORE1 -- per-scanline unpack loop body
PICITEM_MORE1:
    BSR.W	GETUBYTE                              | get packed byteCount
    PEA.L	-0x12C(A6)                            | push addr of buffer
    MOVE.L	(A7),-0x130(A6)                      | put in srcPtr too
    MOVE.W	D0,-(A7)                             | push byteCount
    JSR	GETPICDATA(PC)                          | get packed data
    PEA.L	-0x130(A6)                            | push var srcPtr
    PEA.L	-0x134(A6)                            | push var dstPtr
    MOVE.W	-0x22(A6),-(A7)                      | push rowBytes
    JSR	UNPACKBITS(PC)                          | unpack into HANDLE1 data
PICITEM_START1:
    DBF.W	D6,PICITEM_MORE1                      | loop height rows
    BRA.B	DOBITS                                | continue
| Bit 3 = 0: don't use packing, read bits straight from picture.
PICITEM_NOPACK:
    MOVE.L	(A0),-(A7)                           | push bits ptr
    MOVE.W	D5,-(A7)                             | push byteCount
    JSR	GETPICDATA(PC)                          | get raw bits
DOBITS:
    MOVEA.L	-0x4(A6),A0                         | get HANDLE1
    MOVE.L	(A0),-0x26(A6)                       | install bitmap baseAddr in srcBits
    MOVEA.L	(0x11AC).W,A0                       | _StdBits (bitsProc)
    MOVE.L	0x68(A3),D0                          | is grafProcs nil ?
    BEQ.B	BITSOK                                | yes, use std proc
    MOVEA.L	D0,A0                               | copy pointer
    MOVEA.L	0x20(A0),A0                         | no, get procPtr
BITSOK:
    JSR	(A0)                                    | call bitsProc
    MOVEA.L	-0x4(A6),A0                         | get HANDLE1
    _HUnlock                                    | unlock bits handle
    TST.W	D7                                    | was maskRgn used ?
    BEQ.W	KILL1                                 | no, discard HANDLE1 only
    BRA.W	KILL2                                 | yes, discard HANDLE1 + HANDLE2
| --------------------------------------------------------------------------
|
| CommentOp: OP, KIND, { SIZE, DATA }
|
COMMENTOP:
    BSR.W	GETWORD                               | get comment kind in D0
    MOVE.W	D0,-(A7)                             | push for commentProc
    TST.B	D7                                    | is this short form ?
    BNE.B	LONGCOM                               | no, get more
    CLR.W	-(A7)                                 | yes, push dataSize = 0
    CLR.L	-(A7)                                 | push dataHandle = nil
    MOVEA.L	(0x11C4).W,A0                       | _StdComment (commentProc)
    MOVE.L	0x68(A3),D0                          | is grafProcs nil ?
    BEQ.B	COMMENTOP_OK                          | yes, use std proc
    MOVEA.L	D0,A0                               | copy pointer
    MOVEA.L	0x24(A0),A0                         | no, get procPtr
COMMENTOP_OK:
    BRA.W	CALL0                                 | call no-argument routine
| LONGCOM -- long-form comment ($A1): kind, dataSize, dataHandle
LONGCOM:
    BSR.W	GETWORD                               | get dataSize
    MOVE.W	D0,-(A7)                             | push dataSize
    CLR.W	D4                                    | init byte index for GETHND2
    BSR.W	GETHND2                               | get data into HANDLE1
    MOVE.L	-0x4(A6),-(A7)                       | push data handle
    MOVEA.L	(0x11C4).W,A0                       | _StdComment (commentProc)
    MOVE.L	0x68(A3),D0                          | is grafProcs nil ?
    BEQ.B	LONGCOM_OK                            | yes, use std proc
    MOVEA.L	D0,A0                               | copy pointer
    MOVEA.L	0x24(A0),A0                         | no, get procPtr
LONGCOM_OK:
    BRA.W	CALL1                                 | call one-argument routine

StolenFromAppleRoutine:
| Debugger trigger G 4188A4; copies bitmap then loops forever.
| Easter egg, executable only via debugger trigger "G 4188A4".
| Loads QuickDraw thePort baseAddr (A1) and rowBytes (D0), then
| copies a 32x25 1-bpp "stolen from Apple computer" bitmap into
| the framebuffer one longword per scanline. Spins forever on
| LOOP2 to keep the image displayed.
StolenFromAppleEntrypoint:
    MOVEA.L	(A5),A0                             | point to QD globals
    MOVEA.L	-0x7A(A0),A1                        | A1 = thePort baseAddr (screen)
    MOVE.W	-0x76(A0),D0                         | D0 = rowBytes (per-scanline stride)
    LEA.L	StolenFromAppleBitmap(PC),A0          | A0 = embedded 32x25 bitmap
    MOVEQ.L	#0x18,D1                            | D1 = 24 (loops 25 rows via DBF)
LOOP1:
    MOVE.L	(A0)+,(A1)                           | copy 1 longword (32 px) to screen
    ADDA.W	D0,A1                                | advance to next scanline
    DBF.W	D1,LOOP1                              | loop 25 rows
LOOP2:
    BRA.B	LOOP2                                 | spin forever (image stays on)

StolenFromAppleBitmap:
| 25 rows x 32 pixels embedded bitmap.
StolenFromAppleBitmap_32x25:
    .short	0x0000
    .long	0x00007EE9
    .long	0xD20044A9
    .long	0x1A0074A9
    .long	0x961014A9
    .long	0x123074EF
    .long	0xD2600000
    .long	0x00407774
    .long	0x43584557
    .long	0xC7FC7755
    .long	0x4FFE4654
    .long	0x4FF84574
    .long	0x4FF00000
    .long	0x0FF07774
    .long	0xEFF85554
    .long	0x8FFE7774
    .long	0xCFFE5444
    .long	0x87BC5447
    .long	0xE3180000
    .long	0x00007745
    .long	0xD7FE456D
    .long	0x554A4555
    .long	0xD56E4545
    .long	0x154C7745
    .long	0x1D7A0000
    .short	0x0000
| -----------------------------------------------------
|
| GETDONE -- common N-byte fetch into (A3), then KILL1_EXIT
|
GETDONE:
    MOVE.L	A3,-(A7)                             | push dataPtr
    MOVE.W	D6,-(A7)                             | push byteCount
    JSR	GETPICDATA(PC)                          | get data from thePic
    BRA.W	KILL1_EXIT                            | go to common exit
| ------------------------------------------------------
|
| GETUBYTE -- read an unsigned byte from picture stream into D0
|
| Called by: PICITEM, GET2_CONT_11, TEXTOP, PICITEM_DHOK, TEXTOP2 (and 1 more)
GETUBYTE:
    CLR.B	-(A7)                                 | allocate temp byte
    MOVE.L	A7,-(A7)                             | push addr of temp
    MOVE.W	#0x1,-(A7)                           | push byteCount = 1
    JSR	GETPICDATA(PC)                          | get data from thePic
    CLR.W	D0                                    | get ready for byte
    MOVE.B	(A7)+,D0                             | pop result into lo byte
    RTS                                         | return from GETUBYTE
| ------------------------------------------------------
|
| GETSBYTE -- read a signed byte from picture stream into D0
|
GETSBYTE:
    CLR.B	-(A7)                                 | allocate temp byte
    MOVE.L	A7,-(A7)                             | push addr of temp
    MOVE.W	#0x1,-(A7)                           | push byteCount = 1
    JSR	GETPICDATA(PC)                          | get data from thePic
    MOVE.B	(A7)+,D0                             | pop result
    EXT.W	D0                                    | sign-extend byte to word
    RTS                                         | return from GETSBYTE
| ------------------------------------------------------
|
| GETWORD -- read a word from picture stream into D0
|
| Called by: ARCOP, BITSOP, COMMENTOP, LONGCOM, GETHNDL
GETWORD:
    CLR.W	-(A7)                                 | allocate temp word
    MOVE.L	A7,-(A7)                             | push addr of temp
    MOVE.W	#0x2,-(A7)                           | push byteCount = 2
    JSR	GETPICDATA(PC)                          | get data from thePic
    MOVE.W	(A7)+,D0                             | return answer in D0
    RTS                                         | return from GETWORD
| ------------------------------------------------------
|
| GETLONG -- read a long from picture stream into D0
|
| Called by: GET2_CONT_10, GET2_CONT_9, GET2_CONT_15, GET2_CONT_16, GET2_CONT_17 (and 2 more)
GETLONG:
    CLR.L	-(A7)                                 | allocate temp long
    MOVE.L	A7,-(A7)                             | push addr of temp
    MOVE.W	#0x4,-(A7)                           | push byteCount = 4
    JSR	GETPICDATA(PC)                          | get data from thePic
    MOVE.L	(A7)+,D0                             | return answer in D0
    RTS                                         | return from GETLONG
| ----------------------------------------------------------
|
| GETRECT -- read or repeat an 8-byte rect, map to dst, push addr
|
| If sameFlag is set, reuse the previous theRect.  Otherwise read
| 8 fresh bytes from the picture stream into theRect.  Then map
| through fromRect/toRect into the local DSTRECT and push its addr.
|
GETRECT:
    TST.B	-0x28(A6)                             | sameFlag set ?
    BNE.B	SAME1                                 | yes, reuse theRect
    MOVEA.L	0x8(A6),A2                          | point to playState record
    PEA.L	(A2)                                  | push addr of theRect
    MOVE.W	#0x8,-(A7)                           | push byteCount = 8
    JSR	GETPICDATA(PC)                          | read 8 bytes into theRect
SAME1:
    MOVEA.L	0x8(A6),A2                          | point to playState record
    MOVE.L	(A2),-0x10(A6)                       | copy theRect into dstRect
    MOVE.L	0x4(A2),-0xC(A6)                     | (rect tail)
    PEA.L	-0x10(A6)                             | push local point
    PEA.L	0x14(A2)                              | push fromRect
    PEA.L	0x1C(A2)                              | push toRect
    JSR	MAPRECT(PC)                             | map dstRect
    MOVEA.L	(A7)+,A0                            | pop return addr
    PEA.L	-0x10(A6)                             | push addr of mapped dstRect
    JMP	(A0)                                    | tail-call back
| --------------------------------------------------------
|
| GETHNDL -- read a length-prefixed blob into HANDLE1.
| Reads a 2-byte byteCount, allocates a handle of that size,
| HLocks it, copies (byteCount-D4) bytes from the picture
| stream into offset D4 within the handle, then HUnlocks.
| Used for clipRgn, polyHandle, rgnHandle, comment data,
| maskRgn -- anything stored as length-prefixed bytes.
|
| Tricky entry at GETHND2 with byteCount in D0, D4 = 0.
|
GETHNDL:
    MOVEQ.L	#0x2,D4                             | init byte offset for later
    BSR.B	GETWORD                               | get byteCount
| GETHND2 -- entry with count already in D0
GETHND2:
    EXT.L	D0                                    | make count long
    MOVE.L	D0,D5                                | put byteCount into D5
    _NewHandle                                  | allocate handle
    BNE.W	KILL1_ERR                             | abort if memFull
    MOVE.L	A0,-0x4(A6)                          | remember in HANDLE1
    _HLock                                      | lock it
    MOVEA.L	-0x4(A6),A0                         | get HANDLE1
    MOVEA.L	(A0),A0                             | de-reference
    MOVE.W	D5,(A0)                              | store size header
    SUB.W	D4,D5                                 | leave room for header bytes
    PEA.L	0x0(A0,D4.W)                          | push addr after header
    MOVE.W	D5,-(A7)                             | push remaining byteCount
    JSR	GETPICDATA(PC)                          | get data from thePic
    MOVEA.L	-0x4(A6),A0                         | get HANDLE1
    _HUnlock                                    | unlock it
    RTS                                         | return from GETHND2
| -----------------------------------------------------------------
|
| CALL0 / CALL1 -- call bottleneck proc, dispose temps, quit
|
| Called by: LNOK_OK, TEXTOP2_OK, RECTOP_OK, RRECTOP_OK, OVALOP_OK (and 2 more)
CALL0:
    JSR	(A0)                                    | call no-arg bottleneck
    BRA.B	KILL1_EXIT                            | quit (no temps to discard)
| CALL1 -- call bottleneck, then discard 1 handle temp
CALL1:
    JSR	(A0)                                    | call one-arg bottleneck
    BRA.B	KILL1                                 | discard HANDLE1 and quit
| KILL ONE OR TWO HANDLE TEMPS, THEN EXIT.
KILL2:
    MOVEA.L	-0x8(A6),A0                         | get HANDLE2
    _DisposeHandle                              | discard maskRgn
KILL1:
    MOVEA.L	-0x4(A6),A0                         | get HANDLE1
    _DisposeHandle                              | discard temp handle
    BRA.B	KILL1_EXIT                            | go to common exit
| KILL1_ERR -- abort path: restore SP, return FALSE from PicItem
KILL1_ERR:
    MOVEA.L	-0x138(A6),A7                       | restore SP from save slot
    CLR.B	0xC(A6)                               | return FALSE
| Common exit from PicItem: restore regs, unlink, strip params.
| Called by: PICITEM, GET2_CONT_9, GET2_CONT_10, GET2_CONT_11, GET2_CONT_15 (and 3 more)
KILL1_EXIT:
    MOVEM.L	(A7)+,D3-D7/A2-A4                   | restore registers
    UNLK	A6                                     | release stack frame
    MOVE.L	(A7)+,(A7)                           | strip params, keep return addr
    RTS                                         | return from PicItem
| ------------------------------------------------------
|
| GETPICDATA -- dispatch to current GrafProcs.getPicProc
| or _StdGetPic if grafProcs is nil.
|
| Called by: TEXTOP2, BITSOP, PICITEM_MORE1, PICITEM_NOPACK, GETDONE (and 6 more)
GETPICDATA:
    MOVEA.L	(A5),A0                             | point to QD globals
    MOVEA.L	(A0),A0                             | get current grafPort
    MOVE.L	0x68(A0),D0                          | grafProcs handle
    MOVEA.L	(0x11B8).W,A0                       | _StdGetPic (default)
    BEQ.B	GETPICDATA_STD                        | nil grafProcs, use std
    MOVEA.L	D0,A0                               | copy pointer
    MOVEA.L	0x2C(A0),A0                         | get getPicProc
GETPICDATA_STD:
    JMP	(A0)                                    | tail-call to proc
| ------------------------------------------------------
|
| PUTPICDATA -- dispatch to current GrafProcs.putPicProc
| or _StdPutPic if grafProcs is nil.
|
| Called by: NOPACK, TEXT2, MORE1, MORE2, STDCOMMENT_OK (and 6 more)
PUTPICDATA:
    MOVEA.L	(A5),A0                             | point to QD globals
    MOVEA.L	(A0),A0                             | get current grafPort
    MOVE.L	0x68(A0),D0                          | grafProcs handle
    MOVEA.L	(0x11C0).W,A0                       | _StdPutPic (default)
    BEQ.B	PUTPICDATA_EMPTY                      | nil grafProcs, use std
    MOVEA.L	D0,A0                               | copy pointer
    MOVEA.L	0x30(A0),A0                         | get putPicProc
PUTPICDATA_EMPTY:
    JMP	(A0)                                    | tail-call to proc
| ------------------------------------------------------
|
| Helpers to push N bytes onto the picture stream via PutPicData.
| DPUTPICBYTE accepts byte in D0; PUTPICBYTE/WORD/LONG/PAT/RECT
| accept the value(s) on the stack at +4(SP) and pop them after.
|
| Called by: FONTOK, COUNTOK, FACEOK, STDTEXT_NOTSAME_NO_2, STDRRECT (and 15 more)
DPUTPICBYTE:
    MOVEA.L	(A7)+,A0                            | pop return addr
    MOVE.B	D0,-(A7)                             | push byte from D0
    MOVE.L	A0,-(A7)                             | push return addr back
| Called by: DHDV, PUTOP, NOPACK, MORE1, CLOSEPICTURE
PUTPICBYTE:
    PEA.L	0x4(A7)                               | push addr of byte
    MOVE.W	#0x1,-(A7)                           | push byteCount = 1
    JSR	PUTPICDATA(PC)                          | append to thePic
    MOVEA.L	(A7)+,A0                            | pop return addr
    TST.B	(A7)+                                 | strip byte param
    JMP	(A0)                                    | tail-call back
| Called by: STDARC, STDCOMMENT_OK, COUNTOK, FACEOK, STDTEXT_MODEOK (and 4 more)
PUTPICWORD:
    PEA.L	0x4(A7)                               | push addr of word
    MOVE.W	#0x2,-(A7)                           | push byteCount = 2
    JSR	PUTPICDATA(PC)                          | append to thePic
    MOVEA.L	(A7)+,A0                            | pop return addr
    TST.W	(A7)+                                 | strip word param
    JMP	(A0)                                    | tail-call back
| Called by: STDTEXT_NOTSAME_CONT, PUTOP, STDLINE_STARTOK, STDRRECT, FRAME1 (and 3 more)
PUTPICLONG:
    PEA.L	0x4(A7)                               | push addr of long
    MOVE.W	#0x4,-(A7)                           | push byteCount = 4
    JSR	PUTPICDATA(PC)                          | append to thePic
    MOVE.L	(A7)+,(A7)                           | strip long param
    RTS                                         | return from PUTPICLONG
PUTPICPAT:
    MOVEA.L	(A7)+,A0                            | pop return addr
    MOVE.W	#0x8,-(A7)                           | push byteCount = 8
    MOVE.L	A0,-(A7)                             | push return addr back
    JMP	PUTPICDATA(PC)                          | tail-call PutPicData
| -----------------------------------------------------------
|
| PUTPICRECT(verb, rectAddr) -- compress rect into picture
|
| If the rect equals theRect (last rect put to thePic), set
| sameFlag (verb |= 8) and emit only the verb byte. Otherwise
| emit verb + 8 bytes of rect data.
|
PUTPICRECT:
    MOVEA.L	(A7)+,A0                            | pop return addr
    MOVEA.L	(A7)+,A1                            | pop rect addr
    MOVE.B	(A7)+,D0                             | pop verb byte
    MOVE.L	A0,-(A7)                             | push return addr back
    MOVE.L	(A1),D2                              | get top,left of rect
    MOVE.L	0x4(A1),D1                           | get bottom,right of rect
    MOVEA.L	(A5),A0                             | point to QD globals
    MOVEA.L	(A0),A0                             | get current grafPort
    MOVEA.L	0x5C(A0),A0                         | get PicSave handle
    MOVEA.L	(A0),A0                             | de-reference
    CMP.L	0x4A(A0),D2                           | same top,left ?
    BNE.B	NOTSAME                               | no, emit full rect
    CMP.L	0x4E(A0),D1                           | same bottom,right ?
    BNE.B	NOTSAME                               | no, emit full rect
    ADDQ.W	#0x8,D0                              | yes, set sameRect bit (verb |= 8)
    JMP	DPUTPICBYTE(PC)                         | emit verb only
| NOTSAME -- emit verb byte + 8 bytes of rect coords
NOTSAME:
    MOVE.L	D2,0x4A(A0)                          | save new top,left in PicSave.theRect
    MOVE.L	D1,0x4E(A0)                          | save new bottom,right
    MOVE.L	A1,-(A7)                             | push rect addr
    MOVE.W	#0x8,-(A7)                           | push byteCount = 8
    JSR	DPUTPICBYTE(PC)                         | emit verb byte
    JSR	PUTPICDATA(PC)                          | emit 8 rect bytes
    RTS                                         | return from PUTPICRECT
| -----------------------------------------------------------
|
| PUTPICRGN -- HLock the region handle, emit (length-prefixed)
| rgn data, then HUnlock.
|
PUTPICRGN:
    MOVEA.L	0x4(A7),A0                          | get rgnHandle
    _HLock                                      | lock it
    MOVEA.L	0x4(A7),A0                          | get rgnHandle
    MOVEA.L	(A0),A0                             | de-reference
    MOVE.L	A0,-(A7)                             | push dataPtr
    MOVE.W	(A0),-(A7)                           | push rgn size word
    JSR	PUTPICDATA(PC)                          | emit rgn bytes
    MOVEA.L	0x4(A7),A0                          | get rgnHandle
    _HUnlock                                    | unlock it
    MOVE.L	(A7)+,(A7)                           | strip rgn handle param
    RTS                                         | return from PUTPICRGN
| ----------------------------------------------------------
|
| PROCEDURE PutPicVerb(verb: GrafVerb)
|
| Check additional picture params associated with this verb,
| and add those that have changed to thePic. Verb selects
| which state to compare:
|   0 (frame): pnSize, pnMode, pnPat
|   1 (paint): pnMode, pnPat
|   2 (erase): bkPat
|   3 (invert): nothing
|   4 (fill): fillPat
|
| Called by: STDLINE, STDRECT, STDRRECT, STDOVAL, STDARC (and 2 more)
PUTPICVERB:
    LINK	A6,#0x0                                | no local vars
    MOVEM.L	D5-D7/A3-A4,-(A7)                   | save regs
    MOVEA.L	(A5),A4                             | point to QD globals
    MOVEA.L	(A4),A3                             | get current grafPort
    MOVEA.L	0x5C(A3),A4                         | get PicSave handle
    MOVEA.L	(A4),A4                             | de-reference PicSave
    MOVE.B	0x8(A6),D7                           | get verb param
    CMPI.B	#0x1,D7                              | case jump on verb
    BLT.B	FRAME1                                | < 1: frame
    BEQ.W	PAINT1                                | == 1: paint, check pnMode/pnPat
    CMPI.B	#0x3,D7                              | == 3 (invert) ?
    BEQ.W	PAINT1_EXIT                           | yes, nothing to check
    BLT.B	ERASE1                                | < 3: erase, check bkPat
    MOVE.L	0x28(A3),D5                          | fill: get fillPat
    MOVE.L	0x2C(A3),D6                          | (8 bytes total)
    CMP.L	0x42(A4),D5                           | same as picFillPat ?
    BNE.B	PUTPICVERB_NO                         | no, emit change
    CMP.L	0x46(A4),D6                           | compare with saved pattern tail
    BEQ.W	PAINT1_EXIT                           | if equal, skip
PUTPICVERB_NO:
    MOVE.L	D5,0x42(A4)                          | save new pattern
    MOVE.L	D6,0x46(A4)                          | (pattern tail)
    MOVEQ.L	#0xA,D0                             | fillPat opcode = $0A
    JSR	DPUTPICBYTE(PC)                         | emit opcode
    PEA.L	0x28(A3)                              | push fill pattern addr
    JSR	PUTPICPAT(PC)                           | emit 8 pattern bytes
    BRA.W	PAINT1_EXIT                           | and quit
| ERASE1 -- check bkPat
ERASE1:
    MOVE.L	0x20(A3),D5                          | get bkPat
    MOVE.L	0x24(A3),D6                          | (8 bytes total)
    CMP.L	0x10(A4),D5                           | same as picBkPat ?
    BNE.B	NEWBK                                 | no, emit change
    CMP.L	0x14(A4),D6                           | compare with saved bkPat tail
    BEQ.W	PAINT1_EXIT                           | if equal, skip
NEWBK:
    MOVE.L	D5,0x10(A4)                          | update state variable
    MOVE.L	D6,0x14(A4)                          | (pattern tail)
    MOVEQ.L	#0x2,D0                             | bkPat opcode = $02
    JSR	DPUTPICBYTE(PC)                         | emit opcode
    PEA.L	0x20(A3)                              | push background pattern addr
    JSR	PUTPICPAT(PC)                           | emit 8 pattern bytes
    BRA.B	PAINT1_EXIT                           | and quit
| FRAME1 -- check pnSize, then fall through to PAINT1
FRAME1:
    MOVE.L	0x34(A3),D6                          | get pnSize
    CMP.L	0x34(A4),D6                           | has it changed ?
    BEQ.B	PAINT1                                | no, continue to pnMode
    MOVEQ.L	#0x7,D0                             | pnSize opcode = $07
    JSR	DPUTPICBYTE(PC)                         | emit opcode
    MOVE.L	D6,-(A7)                             | push new pnSize
    JSR	PUTPICLONG(PC)                          | emit 4 bytes
    MOVEA.L	0x5C(A3),A4                         | re-fetch PicSave handle
    MOVEA.L	(A4),A4                             | (heap may have moved)
    MOVE.L	D6,0x34(A4)                          | update state variable
PAINT1:
    MOVE.W	0x38(A3),D6                          | get pnMode
    CMP.W	0x38(A4),D6                           | has it changed ?
    BEQ.B	PAINT1_NO                             | no, continue
    MOVEQ.L	#0x8,D0                             | pnMode opcode = $08
    JSR	DPUTPICBYTE(PC)                         | emit opcode
    MOVE.W	D6,-(A7)                             | push new pnMode
    JSR	PUTPICWORD(PC)                          | emit 2 bytes
    MOVEA.L	0x5C(A3),A4                         | re-fetch PicSave handle
    MOVEA.L	(A4),A4                             | (heap may have moved)
    MOVE.W	D6,0x38(A4)                          | update state variable
PAINT1_NO:
    MOVE.L	0x3A(A3),D5                          | get pnPat
    MOVE.L	0x3E(A3),D6                          | (8 bytes total)
    CMP.L	0x3A(A4),D5                           | same as picPnPat ?
    BNE.B	PAINT1_NO_2                           | no, emit change
    CMP.L	0x3E(A4),D6                           | compare with saved pnPat tail
    BEQ.B	PAINT1_EXIT                           | if equal, skip
PAINT1_NO_2:
    MOVE.L	D5,0x3A(A4)                          | save new pnPat
    MOVE.L	D6,0x3E(A4)                          | (pattern tail)
    MOVEQ.L	#0x9,D0                             | pnPat opcode = $09
    JSR	DPUTPICBYTE(PC)                         | emit opcode
    PEA.L	0x3A(A3)                              | push pen pattern addr
    JSR	PUTPICPAT(PC)                           | emit 8 pattern bytes
| Common epilog for PutPicVerb branches.
| Called by: PUTPICVERB, PUTPICVERB_NO, ERASE1, NEWBK, PAINT1_NO
PAINT1_EXIT:
    MOVEM.L	(A7)+,D5-D7/A3-A4                   | restore regs
    UNLK	A6                                     | release stack frame
    MOVEA.L	(A7)+,A0                            | get return address
    ADDQ.W	#0x2,A7                              | pop verb param
    JMP	(A0)                                    | tail-call back
| ----------------------------------------------------------
|
| PROCEDURE CheckPic
|
| Called from every StdXxx routine (StdLine/StdRect/etc.) before
| writing geometry. Returns flags LE if not recording (PicSave
| nil or pen hidden). Otherwise checks fgColor, bkColor, origin,
| and clipRgn against last-written values; emits opcodes for any
| that have changed and updates state, then returns flags GT.
|
| Called by: COUNTOK, STDLINE, STDRECT, STDRRECT, STDOVAL (and 4 more)
CHECKPIC:
    MOVE.L	D7,-(A7)                             | save regs
    MOVEA.L	(A5),A4                             | point to QD globals
    MOVEA.L	(A4),A3                             | get current grafPort
    TST.L	0x5C(A3)                              | are we saving for a picture ?
    BEQ.W	ORIGNOK_EXIT_2                        | no, return flags LE and quit
    CMPI.W	#0xFFFF,0x42(A3)                     | is pen hidden more than 1 ?
    BLT.W	ORIGNOK_EXIT_2                        | yes, don't add to thePic
    MOVEA.L	0x5C(A3),A4                         | get PicSave handle
    MOVEA.L	(A4),A4                             | de-reference PicSave
| Check for changes in foreground color.
    MOVE.L	0x50(A3),D7                          | get fgColor
    CMP.L	0x5A(A4),D7                           | has it changed ?
    BEQ.B	CHECKPIC_NO                           | no, continue
    MOVEQ.L	#0xE,D0                             | fgColor opcode = $0E
    JSR	DPUTPICBYTE(PC)                         | emit opcode
    MOVE.L	D7,-(A7)                             | push color
    JSR	PUTPICLONG(PC)                          | emit fgColor (4 bytes)
    MOVEA.L	0x5C(A3),A4                         | re-fetch PicSave handle
    MOVEA.L	(A4),A4                             | (heap may have moved)
    MOVE.L	D7,0x5A(A4)                          | update state variable
| Check for changes in background color.
CHECKPIC_NO:
    MOVE.L	0x54(A3),D7                          | get bkColor
    CMP.L	0x5E(A4),D7                           | has it changed ?
    BEQ.B	CHECKPIC_NO_2                         | no, continue
    MOVEQ.L	#0xF,D0                             | bkColor opcode = $0F
    JSR	DPUTPICBYTE(PC)                         | emit opcode
    MOVE.L	D7,-(A7)                             | push color
    JSR	PUTPICLONG(PC)                          | emit bkColor (4 bytes)
    MOVEA.L	0x5C(A3),A4                         | re-fetch PicSave handle
    MOVEA.L	(A4),A4                             | (heap may have moved)
    MOVE.L	D7,0x5E(A4)                          | update state variable
| Check for origin changes (portRect.topLeft vs picOrigin).
CHECKPIC_NO_2:
    MOVE.L	0x10(A3),D0                          | get portRect.topLeft
    CMP.L	0x56(A4),D0                           | same as picOrigin ?
    BEQ.B	ORIGNOK                               | yes, continue
    MOVE.W	0x12(A3),D7                          | get portRect.left
    SUB.W	0x58(A4),D7                           | calc dh
    ADD.W	D7,0x58(A4)                           | update state variable
    SWAP.W	D7                                   | put dh in hi word
    MOVE.W	0x10(A3),D7                          | get portRect.top
    SUB.W	0x56(A4),D7                           | calc dv
    ADD.W	D7,0x56(A4)                           | update state variable
    MOVEQ.L	#0xC,D0                             | origin opcode = $0C
    JSR	DPUTPICBYTE(PC)                         | emit opcode
    MOVE.L	D7,-(A7)                             | push dh,dv
    JSR	PUTPICLONG(PC)                          | emit (4 bytes)
    MOVEA.L	0x5C(A3),A4                         | re-fetch PicSave handle
    MOVEA.L	(A4),A4                             | (heap may have moved)
| Check for clipRgn changes via EqualRgn.
ORIGNOK:
    CLR.B	-(A7)                                 | room for fcn result
    MOVE.L	0x1C(A3),-(A7)                       | push thePort.clipRgn
    MOVE.L	0xC(A4),-(A7)                        | push picClipRgn
    JSR	EQUALRGN(PC)                            | are they equal ?
    TST.B	(A7)+                                 | test result
    BNE.B	CLIPOK                                | yes, skip
    MOVE.L	0x1C(A3),-(A7)                       | push clipRgn for CopyRgn below
    MOVE.L	0xC(A4),-(A7)                        | push picClipRgn dst
    MOVEQ.L	#0x1,D0                             | clipRgn opcode = $01
    JSR	DPUTPICBYTE(PC)                         | emit opcode
    MOVE.L	0x1C(A3),-(A7)                       | push clipRgn handle
    JSR	PUTPICRGN(PC)                           | emit clipRgn data
    JSR	COPYRGN(PC)                             | copy clipRgn into picClipRgn
CLIPOK:
    MOVEA.L	(A5),A4                             | point to QD globals
    MOVEQ.L	#0x1,D0                             | clear zero flag (return GT)
ORIGNOK_EXIT_2:
    MOVEM.L	(A7)+,D7                            | restore reg + set CC from D7
    RTS                                         | return from SCSIREADBLOCKS
| -------------------------------------------------------------
|
| PROCEDURE ScalePt(VAR pt: Point; fromRect, toRect: Rect)
|
| Scale a width and height from one coordinate system to another.
| If fromRect and toRect are the same size, then no change.
| If the input > 0, then enforce 1 pixel minimum on the output.
|
|   pt.h := (pt.h * toWidth) / fromWidth
|   pt.v := (pt.v * toHeight) / fromHeight
|
| Restores all registers.
|
SCALEPT:
    LINK	A6,#0x0                                | no locals
    MOVEM.L	D0-D6/A0-A2,-(A7)                   | save regs
    MOVEA.L	0x10(A6),A0                         | point to var pt
    MOVEA.L	0xC(A6),A1                          | point to fromRect
    MOVEA.L	0x8(A6),A2                          | point to toRect
    BSR.B	SCALE1                                | scale the height
    ADDQ.W	#0x2,A0                              | offset to pt.h
    ADDQ.W	#0x2,A1                              | offset to fromRect.h
    ADDQ.W	#0x2,A2                              | offset to toRect.h
    BSR.B	SCALE1                                | scale the width
    MOVEM.L	(A7)+,D0-D6/A0-A2                   | restore regs
    UNLK	A6                                     | release stack frame
    MOVEA.L	(A7)+,A0                            | get return address
    ADDA.W	#0xC,A7                              | pop parameters
    JMP	(A0)                                    | tail-call return from SCALEPT via A0
| -------------------------------------------------------
|
| SCALE1 -- scale a single width or height
| If input <= 0, then output will be 0.
| If input > 0, then output will be at least 1.
|
SCALE1:
    MOVE.W	0x4(A1),D3                           | get fromRect bottom
    SUB.W	(A1),D3                               | calc fromHeight
    MOVE.W	0x4(A2),D2                           | get toRect bottom
    SUB.W	(A2),D2                               | calc toRect height
    CMP.W	D2,D3                                 | are both heights the same ?
    BEQ.B	SCDONE                                | yes, skip
    MOVE.W	D3,D1                                | copy denom = fromHeight
    LSR.W	#0x1,D1                               | calc denom/2 (denom is pos)
    EXT.L	D1                                    | make it long
    MOVE.W	(A0),D0                              | get size coord
    BGT.B	POS                                   | continue if positive
    CLR.W	(A0)                                  | else set it to zero
    RTS                                         | and quit
| POS -- positive input, do scale + 1-pixel-min enforcement
POS:
    MULU.W	D2,D0                                | mult by toRect height
    ADD.L	D1,D0                                 | add fromHeight/2 for rounding
    DIVU.W	D3,D0                                | div by fromHeight
    BNE.B	MINSIZE_EMPTY                         | non-zero result, store as-is
    MOVEQ.L	#0x1,D0                             | enforce 1 pixel min size
MINSIZE_EMPTY:
    MOVE.W	D0,(A0)                              | sizeOk: update result
SCDONE:
    RTS                                         | return from SCALE1
| -------------------------------------------------------------
|
| PROCEDURE MapPt(VAR pt: Point; fromRect, toRect: Rect)
|
| Map a point from one coordinate system to another.
|
|   pt.h := ((pt.h-fromLeft)*toWidth)  /fromWidth  + toLeft
|   pt.v := ((pt.v-fromTop) *toHeight) /fromHeight + toTop
|
| Restores all registers.
|
| Called by: MAPRECT, MAPPOLY_NEXTPT, MAPRGN_LOOP, LNFROM, LNOK (and 1 more)
MAPPT:
    LINK	A6,#0x0                                | no locals
    MOVEM.L	D0-D6/A0-A2,-(A7)                   | save regs
    MOVEA.L	0x10(A6),A0                         | point to var pt
    MOVEA.L	0xC(A6),A1                          | point to fromRect
    MOVEA.L	0x8(A6),A2                          | point to toRect
    BSR.B	MAP1                                  | map the vertical coord
    ADDQ.W	#0x2,A0                              | offset to pt.h
    ADDQ.W	#0x2,A1                              | offset to fromRect.h
    ADDQ.W	#0x2,A2                              | offset to toRect.h
    BSR.B	MAP1                                  | map the horizontal coord
    MOVEM.L	(A7)+,D0-D6/A0-A2                   | restore regs
    UNLK	A6                                     | release stack frame
    MOVEA.L	(A7)+,A0                            | get return address
    ADDA.W	#0xC,A7                              | pop parameters
    JMP	(A0)                                    | tail-call return from MAPPT via A0
| MAP1 -- map a single coord through fromRect -> toRect
MAP1:
    MOVE.W	(A1),D2                              | get fromRect.top
    MOVE.W	0x4(A1),D3                           | get fromRect.bottom
    SUB.W	D2,D3                                 | calc fromHeight
    MOVE.W	(A2),D4                              | get toRect.top
    MOVE.W	0x4(A2),D5                           | get toRect.bottom
    SUB.W	D4,D5                                 | calc toHeight
    MOVE.W	(A0),D0                              | get pt coord
    SUB.W	D2,D0                                 | bias by -fromTop
    CMP.W	D3,D5                                 | same height ?
    BEQ.B	NOSCALE                               | yes, skip the math
    MOVE.W	D3,D1                                | copy denom = fromHeight
    LSR.W	#0x1,D1                               | calc denom/2 for rounding
    EXT.L	D1                                    | make it long
    MOVE.W	D0,D2                                | save sign of biased coord
    BPL.B	NOTNEG                                | if pos, leave alone
    NEG.W	D0                                    | else absolute-value it
NOTNEG:
    MULU.W	D5,D0                                | * toHeight
    ADD.L	D1,D0                                 | + fromHeight/2
    DIVU.W	D3,D0                                | / fromHeight
    TST.W	D2                                    | restore sign
    BPL.B	NOSCALE                               | if pos, leave result
    NEG.W	D0                                    | else negate result
NOSCALE:
    ADD.W	D4,D0                                 | bias by +toTop
    MOVE.W	D0,(A0)                              | store mapped coord
    RTS                                         | return from MAP1
| -------------------------------------------------------------
|
| PROCEDURE MapRect(VAR r: Rect; fromRect, toRect: Rect)
|
| Map both corners of a rect by calling MapPt twice. Manipulates
| the call-site stack so each MapPt call sees: ptAddr, fromRect,
| toRect.
|
| Called by: NOSLOP, DOWN2, MAPPOLY_NOTSAME, MAPRGN_NO, BITSOP (and 1 more)
MAPRECT:
    MOVE.L	0xC(A7),-(A7)                        | re-push toRect addr
    MOVE.L	0xC(A7),-(A7)                        | re-push fromRect addr
    MOVE.L	0xC(A7),-(A7)                        | re-push rect addr
    JSR	MAPPT(PC)                               | map top-left
    ADDQ.L	#0x4,0xC(A7)                         | bump rectAddr by +4 to bot-right
    JMP	MAPPT(PC)                               | tail-call: map bot-right
| -------------------------------------------------------------
|
| MAPRATIO(VAR numer, denom: Point; srcRect: Rect)
|
| Adjust txRatio (numer/denom) for a rect-to-rect mapping. Used
| by GET2_CONT_10 (txRatio opcode) when playing a picture into
| a destination rect of different size.
|
MAPRATIO:
    LINK	A6,#0x0                                | no locals
    MOVEM.L	D0-D1/A0-A2,-(A7)                   | save regs
    MOVEA.L	0x10(A6),A0                         | point to numer
    MOVEA.L	0xC(A6),A1                          | point to denom
    MOVEA.L	0x8(A6),A2                          | point to srcRect
    MOVE.W	0x6(A2),D0                           | get srcRect.right
    SUB.W	0x2(A2),D0                            | calc srcWidth
    MOVE.W	0x2(A0),D1                           | get numer.h
    MULU.W	D0,D1                                | numer.h * srcWidth
    DIVU.W	0x2(A1),D1                           | / denom.h
    MOVE.W	D1,0x2(A0)                           | -> numer.h
    MOVE.W	D0,0x2(A1)                           | denom.h := srcWidth
    MOVE.W	0x4(A2),D0                           | get srcRect.bottom
    SUB.W	(A2),D0                               | calc srcHeight
    MOVE.W	(A0),D1                              | get numer.v
    MULU.W	D0,D1                                | numer.v * srcHeight
    DIVU.W	(A1),D1                              | / denom.v
    MOVE.W	D1,(A0)                              | -> numer.v
    MOVE.W	D0,(A1)                              | denom.v := srcHeight
    MOVEM.L	(A7)+,D0-D1/A0-A2                   | restore regs
    UNLK	A6                                     | release stack frame
    MOVEA.L	(A7)+,A0                            | get return address
    ADDA.W	#0xC,A7                              | pop parameters
    JMP	(A0)                                    | tail-call return from MAPRATIO via A0
