| Printing Manager glue -- _PrGlue
|
| Apple source: PrintGlue.a (System 7.1: Toolbox/Printing/PrintGlue.a;
| MacSEROM.lst module PRGLUE). The _PrGlue trap ($A8FD), new with the SE:
| the Printing Manager calls (PrOpen, PrClose, PrOpenDoc, ...) are one
| trap with a selector; the glue opens the printer driver's PDEF code
| ('PDEF' resources of the current printer resource file) and jumps to the
| routine. Before the SE these calls were linked into each application.
|
| References: Inside Macintosh Vol V, Ch 22 (The Printing Manager)

| ----------------------------------------------------------
| _PrGlue ($A8FD) - Print Manager dispatcher (both SE ROMs)
| Stack frame after LINK A6,#0:
|   0x8(A6)  byte: dispatch byte. Bit 7 = built-in path,
|                  bits 6..3 = entry index (* 2 -> PRGLUE_DISPATCH_TBL),
|                  bits 2..0 = param-restore size class.
|   0x9(A6)  byte: PDEF resource ID for high-level path
|   0xA(A6)  byte: param-bytes count returned to caller stack
|   0xB(A6)  byte: PDEF entry offset; bit 7 set => unlock the PDEF after the call
|   0xC(A6).. parameters (variable count, copied to local stack)
| Two dispatch paths:
|   (1) Negative bit 7 in 0x8(A6): built-in entry via PRGLUE_DISPATCH_TBL
|   (2) Else: load 'PDEF' resource D2, copy params, JSR PDEF[offset].
| The dispatcher saves A3-A4, builds a local copy of the parameters,
| calls the worker, and on exit copies (size & 7) bytes back to the
| caller's stack and pops the variable-sized parameter block.
PRGLUE:
    LINK	A6,#0x0                                | establish frame
    MOVEM.L	A3-A4,-(SP)                         | save callee-saved
    MOVEQ.L	#0x0,D1                             | clear D1
    MOVE.B	0x8(A6),D1                           | D1 = dispatch byte
    LSR.B	#0x3,D1                               | D1 = entry index (bits 6..3 originally)
    BEQ.B	PRG_FROM_DCE                          | index 0 -> use DCE-stored PDEF id
    TST.B	0x8(A6)                               | bit 7 set?
    BMI.B	PRG_BUILTIN_DISPATCH                  | yes -> built-in entry table
    MOVEQ.L	#0x0,D2                             | clear D2
    MOVE.B	0x9(A6),D2                           | D2 = PDEF id from caller
    BNE.B	PRG_LOAD_PDEF                         | nonzero -> use it directly
    MOVEQ.L	#0x3,D2                             | else: low 2 bits of PrFlags
    AND.B	(PrFlags).W,D2                        | D2 = current Print PDEF id
    BRA.B	PRG_LOAD_PDEF                         | -> load it
PRG_FROM_DCE:
    MOVEA.L	0x14(A6),A0                         | A0 -> printer DCE handle
    MOVEA.L	(A0),A0                             | A0 -> DCE record
    MOVEQ.L	#0x3,D2                             | mask low 2 bits
    AND.B	0x44(A0),D2                           | D2 = DCE's PDEF id
    ANDI.B	#0xFC,(PrFlags).W                    | clear PrFlags low 2 bits
    OR.B	D2,(PrFlags).W                         | install new PDEF id
PRG_LOAD_PDEF:
    CLR.L	-(SP)                                 | reserve handle result
    MOVE.L	#0x50444546,-(SP)                    | type 'PDEF'
    MOVE.W	D2,-(SP)                             | id = D2
    _GetResource                                | load 'PDEF' D2
    MOVE.L	(SP)+,D0                             | D0 = resource handle
    BNE.B	PRG_GOT_PDEF                          | success
    MOVE.W	#0xFF40,(PrintErr).W                 | -0xC0 = resNotFound
    BRA.W	PRG_EXIT_NO_RESULT                    | -> exit
PRG_GOT_PDEF:
    MOVEA.L	D0,A4                               | A4 = PDEF handle
    MOVEA.L	A4,A0                               | _HLock(A4)
    _HLock                                      | lock PDEF for in-place call
    LEA.L	0xC(A6),A0                            | A0 -> caller's params on stack
    MOVEQ.L	#0x7,D0                             | low 3 bits of dispatch byte
    AND.B	0x8(A6),D0                            | D0 = restore-bytes class
    ADD.B	0xA(A6),D0                            | + caller param size
    SUBA.W	D0,SP                                | reserve local copy
    MOVEA.L	SP,A1                               | A1 -> local copy
    _BlockMove                                  | copy params to local stack
    MOVE.B	0xB(A6),D0                           | D0 = PDEF entry offset (+ unlock flag)
    ANDI.B	#0x7F,D0                             | strip the unlock flag (bit 7)
    MOVEA.L	(A4),A0                             | A0 = PDEF code base
    JSR	0x0(A0,D0.W)                            | call PDEF[entry]
    MOVE.B	0xB(A6),D0                           | test the unlock flag (bit 7)
    BPL.B	PRG_PDEF_KEEP_LOCKED                  | clear: leave the PDEF locked ->
    MOVEA.L	A4,A0                               | A0 = PDEF handle
    _HUnlock                                    | unlock the PDEF again (it may move or be purged)
PRG_PDEF_KEEP_LOCKED:
    BRA.W	PRG_EPILOGUE                          | -> common epilogue
| ----------------------------------------------------------
| Built-in dispatch: D1 = (dispatch_byte >> 3) & 0xF
| (Bit 4 of D1 cleared inline -> 4-bit entry select; word offset
|  in PRGLUE_DISPATCH_TBL.) Allocates a 0x32-byte ParamBlock on stack with
| ioName -> "/.Print" string and ioVRefNum = 0xFFFD (any volume).
PRG_BUILTIN_DISPATCH:
    SUBA.W	#0x32,SP                             | reserve ParamBlock on stack
    LEA.L	PrintDriverName_Str(PC),A0            | A0 -> ".Print" str literal
    MOVE.L	A0,0x12(SP)                          | ioName -> ".Print"
    MOVE.W	#0xFFFD,0x18(SP)                     | ioVRefNum = -3 (any disk)
    CLR.B	0x1B(SP)                              | ioPermssn = 0
    MOVEA.L	SP,A0                               | A0 = ParamBlock
    MOVEQ.L	#0x0,D0                             | clear D0
    BCLR	#0x4,D1                                | mask to 4-bit selector
    ADD.W	D1,D1                                 | D1 *= 2 (word stride)
    MOVE.W	PRGLUE_DISPATCH_TBL(PC,D1.W),D1      | D1 = entry offset
    JMP	PRGLUE_DISPATCH_TBL(PC,D1.W)            | jump to PrGlue_<id>
| ----------------------------------------------------------
| Built-in dispatch table (14 entries; 4 unused slots default to
| PrGlue_FAIL = -50). Each entry is the offset from PRGLUE_DISPATCH_TBL.
PRGLUE_DISPATCH_TBL:
    .long	0x0096009A                            | sel 0,1: PrGlue_OPEN, PrGlue_CLOSE
    .long	0x009E00A8                            | sel 2,3: PrGlue_STATUS, PrGlue_ATTR
    .long	0x00BA00D6                            | sel 4,5: PrGlue_CONTROL, PrGlue_PURGE
    .long	0x00E80108                            | sel 6,7: PrGlue_NOPURGE, PrGlue_GETERR
    .long	0x01120030                            | sel 8,9: PrGlue_PASSTHRU (PrSetError), PrGlue_PROPEN (PrOpen)
    .long	0x003E0020                            | sel 10,11: PrGlue_PRCLOSE (PrClose), PrGlue_FAIL
    .long	0x00200020                            | sel 12,13: PrGlue_FAIL, PrGlue_FAIL
    .long	0x00200020                            | sel 14,15: PrGlue_FAIL, PrGlue_FAIL
| ----------------------------------------------------------
| PrGlue_FAIL: store paramErr (-50 = 0xFFCE) and skip param copy.
PrGlue_FAIL:
    MOVE.W	#0xFFCE,(PrintErr).W                 | paramErr
PRG_EXIT_NO_RESULT:
    MOVEQ.L	#0x0,D1                             | D1 = 0 (no built-in stack to drop)
    MOVE.B	0xA(A6),D1                           | D1 = restore-bytes count
    BRA.W	PRG_FRAME_RESTORE                     | skip copyback, restore frame
| ----------------------------------------------------------
| PrGlue_PROPEN (selector 25, PrOpen): open the .Print driver, then
| the current printer resource file (PRG_OPEN_RF_BODY).
PrGlue_PROPEN:
    MOVE.L	#0x80000000,-(SP)                    | glue long: selector 16 = PrDrvrOpen
    _PrGlue                                     | _PrDrvrOpen: open the .Print driver
    BNE.B	PRG_OPEN_FAIL                         | error -> PrintErr
    MOVEQ.L	#0x0,D1                             | D1 = 0: keep the file open
    BRA.B	PRG_OPEN_RF_BODY                      | -> shared body
| ----------------------------------------------------------
| PrGlue_PRCLOSE (selector 26, PrClose): close the .Print driver, then
| open the printer resource file again to learn its refNum and close it.
PrGlue_PRCLOSE:
    MOVE.L	#0x88000000,-(SP)                    | glue long: selector 17 = PrDrvrClose
    _PrGlue                                     | _PrDrvrClose: close the .Print driver
    MOVEQ.L	#0x1,D1                             | D1 = 1: close the file again
PRG_OPEN_RF_BODY:
    SUBQ.W	#0x4,SP                              | room for the _GetString result
    MOVE.W	#0xE000,-(SP)                        | ID -8192: 'STR ' with the printer resource file name
    _GetString                                  | get its handle
    MOVE.L	(SP)+,D0                             | D0 = string handle
    BNE.B	PRG_GOT_NAME                          | success
    MOVE.W	#0xFF40,D0                           | resNotFound
    BRA.B	PRG_OPEN_FAIL                         | -> error exit
PRG_GOT_NAME:
    MOVEA.L	D0,A1                               | A1 = name handle
    BSR.W	PRGLUE_GET_VREFNUM                    | save current default vol
    SWAP.W	D1                                   | move flag to high half of D1
    MOVE.W	D0,D1                                | low half = old VRefNum
    SUBQ.W	#0x2,SP                              | reserve refNum result
    MOVEA.L	A1,A0                               | A0 = the file name handle
    _HLock                                      | lock it: _OpenRFPerm gets a pointer into it
    MOVE.L	(A1),-(SP)                           | push the file name
    CLR.W	-(SP)                                 | vRefNum = 0 (default vol)
    CLR.B	-(SP)                                 | permission = read-only
    _OpenRFPerm                                 | open the printer resource file
    MOVEA.L	A1,A0                               | A0 = the file name handle
    _HUnlock                                    | unlock it again
    MOVE.W	D1,D0                                | restore old VRefNum
    SWAP.W	D1                                   | flag back to D1.L bit
    BSR.W	PRGLUE_SET_VOL                        | restore default volume
    MOVE.W	(SP)+,D0                             | pop refNum
    TST.W	(ResErr).W                            | open succeeded?
    BNE.B	PRG_OPEN_DONE                         | no -> ResErr is the answer
    TST.W	D1                                    | close-after flag set?
    BEQ.B	PRG_OPEN_DONE                         | no -> keep open
    MOVE.W	D0,-(SP)                             | push refNum
    _CloseResFile                               | close it
PRG_OPEN_DONE:
    MOVE.W	(ResErr).W,D0                        | result = ResErr
PRG_OPEN_FAIL:
    BRA.W	PRG_STORE_ERR                         | -> common epilogue
| ----------------------------------------------------------
| PrGlue_OPEN: simple _Open passthrough; ParamBlock already on stack.
PrGlue_OPEN:
    _Open                                       | _Open driver
    BRA.B	PRG_STORE_ERR                         | -> store result
PrGlue_CLOSE:
    _Close                                      | _Close driver
    BRA.B	PRG_STORE_ERR                         | -> store result
| ----------------------------------------------------------
| PrGlue_STATUS: _Status with cs=1 -> get DCE handle, return it.
PrGlue_STATUS:
    BSR.B	PRG_STATUS_DCE                        | A0 = DCE handle
    ADDA.W	#0x2E,SP                             | drop ParamBlock - 4 (keep result)
    MOVE.L	A0,(SP)                              | result = DCE handle
    BRA.B	PRG_EPILOGUE                          | -> exit (no PrintErr update)
| ----------------------------------------------------------
| PrGlue_ATTR: read DCE byte 0x7 (driver flags / ID), return word.
PrGlue_ATTR:
    BSR.B	PRG_STATUS_DCE                        | A0 = DCE
    MOVEA.L	(A0),A0                             | dereference handle
    MOVEQ.L	#0x0,D0                             | clear high
    MOVE.B	0x7(A0),D0                           | D0.B = DCE flags byte
    ADDA.W	#0x30,SP                             | drop ParamBlock - 2
    MOVE.W	D0,(SP)                              | result word = flags
    BRA.B	PRG_EPILOGUE                          | -> exit
| ----------------------------------------------------------
| PrGlue_CONTROL: copy 4 longs + 1 word from caller to ParamBlock,
| then call _Control.
PrGlue_CONTROL:
    MOVE.L	0xC(A6),0x24(A0)                     | csParam[0..3] = caller's longs
    MOVE.L	0x10(A6),0x20(A0)                    | csParam[4..7]
    MOVE.L	0x14(A6),0x1C(A0)                    | csParam[8..11]
    MOVE.W	0x18(A6),0x1A(A0)                    | csCode
    _Control                                    | _Control driver
    BRA.B	PRG_STORE_ERR                         | -> store result
| ----------------------------------------------------------
| PrGlue_PURGE: _Status -> DCE; if dRAMBased (bit 6 of flags), _HPurge
| the driver storage handle.
PrGlue_PURGE:
    BSR.B	PRG_STATUS_DCE                        | A0 = DCE
    MOVEA.L	(A0),A0                             | dereference
    BTST	#0x6,0x5(A0)                           | dRAMBased?
    BEQ.B	PRG_STORE_ERR                         | no -> done
    MOVEA.L	(A0),A0                             | A0 = driver handle
    _HPurge                                     | _HPurge it
    BRA.B	PRG_STORE_ERR                         | -> done
| ----------------------------------------------------------
| PrGlue_NOPURGE: same as PURGE but _HNoPurge.
PrGlue_NOPURGE:
    BSR.B	PRG_STATUS_DCE                        | A0 = DCE
    MOVEA.L	(A0),A0                             | dereference
    BTST	#0x6,0x5(A0)                           | dRAMBased?
    BEQ.B	PRG_STORE_ERR                         | no -> done
    MOVEA.L	(A0),A0                             | A0 = driver handle
    _HNoPurge                                   | _HNoPurge it
    BRA.B	PRG_STORE_ERR                         | -> done
| ----------------------------------------------------------
| PRG_STATUS_DCE - call _Status with csCode=1 to get DCE handle.
| Returns A0 = DCE handle.
PRG_STATUS_DCE:
    MOVE.W	#0x1,0x1A(A0)                        | csCode = 1 (drvrStatusGetDCE)
    _Status                                     | _Status driver
    MOVEA.L	0x1C(A0),A0                         | A0 = DCE handle from csParam
    RTS                                         | return from PRG_STATUS_DCE
| ----------------------------------------------------------
| PrGlue_GETERR: return current PrintErr lowmem global.
PrGlue_GETERR:
    ADDA.W	#0x30,SP                             | drop ParamBlock - 2
    MOVE.W	(PrintErr).W,(SP)                    | result = PrintErr
    BRA.B	PRG_EPILOGUE                          | -> exit
| ----------------------------------------------------------
| PrGlue_PASSTHRU: caller's first param word becomes result code.
PrGlue_PASSTHRU:
    MOVE.W	0xC(A6),D0                           | D0 = caller's first param (status)
| ----------------------------------------------------------
| PRG_STORE_ERR - store D0 into PrintErr, drop ParamBlock, fall into
| epilogue.
| Called by: PrGlue_PURGE, PrGlue_NOPURGE, PRG_OPEN_FAIL, PrGlue_OPEN, PrGlue_CLOSE (and 1 more)
PRG_STORE_ERR:
    ADDA.W	#0x32,SP                             | drop full ParamBlock
    MOVE.W	D0,(PrintErr).W                      | persist last error
PRG_EPILOGUE:
    MOVEQ.L	#0x0,D1                             | clear D1
    MOVE.B	0xA(A6),D1                           | D1 = caller restore-bytes
PRG_EPILOGUE_FRAME:
    MOVEQ.L	#0x7,D0                             | low 3 bits of dispatch
    AND.B	0x8(A6),D0                            | D0 = local-copy size
    BEQ.B	PRG_FRAME_RESTORE                     | none -> skip copyback
    MOVE.W	D0,D2                                | save copy size
    MOVEA.L	SP,A0                               | A0 = local results
    LEA.L	0xC(A6,D1.W),A1                       | A1 = caller's result slot
    _BlockMove                                  | copy results back
    ADDA.W	D2,SP                                | drop the copy
PRG_FRAME_RESTORE:
    MOVEM.L	(SP)+,A3-A4                         | restore callee-saved
    UNLK	A6                                     | release frame
    MOVEA.L	(SP)+,A0                            | pop trap return addr
    ADDA.L	D1,SP                                | drop caller param block
    ADDQ.W	#0x4,SP                              | drop dispatch-byte longword
    JMP	(A0)                                    | tail-call return from PRG_FRAME_RESTORE via A0
| ----------------------------------------------------------
|
| PRGLUE_GET_VREFNUM
|
| PRGLUE_GET_VREFNUM: get current volume VRefNum (returns in D0)
PRGLUE_GET_VREFNUM:
    MOVEQ.L	#0x0,D0                             | D0 = 0 (use default volume)
| PRGLUE_SET_VOL: set volume to D0, then get current volume back
PRGLUE_SET_VOL:
    SUBA.W	#0x40,SP                             | reserve 64-byte ParamBlockRec on stack
    MOVEA.L	SP,A0                               | A0 -> ParamBlock (ioParam union)
    MOVE.W	D0,0x16(A0)                          | ioVRefNum = requested vol
    CLR.L	0x12(A0)                              | ioNamePtr = nil
    _SetVol                                     | switch to requested volume
    _GetVol                                     | get current vol back into ioVRefNum
    MOVE.W	0x16(A0),D0                          | D0 = previously-current VRefNum
    ADDA.W	#0x40,SP                             | release ParamBlock
    RTS                                         | return previous VRefNum in D0
| ----------------------------------------------------------
| PrintDriverName_Str: Pascal-format string ".Print" used by InitPack5 to
| open the printer driver via _Open after pushing a pointer to it.
PrintDriverName_Str:
    .long	0x062E5072                            | ".Pr" (length=6)
    .long	0x696E7420                            | "int "
