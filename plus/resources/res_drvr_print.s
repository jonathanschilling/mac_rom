| DRVR 2 - .Print driver
| resource : 'DRVR' 2 '.Print'
|
| Printer Driver Shell: stub that forwards all calls to the
| actual printer driver (loaded from PRER resource in System file).
| Each entry point loads the PRER resource and jumps to the
| corresponding offset within it. If PRER not found, returns noErr.

| resource header
        .long   0xC0000174                      | ROM resource header: tag $C0, physical size $174 (8 + $16C)
        .long   0x00000054                      | relative handle: master pointer at ROM zone + $54
_DRVR_2_.Print:
  .short 0x4F00                                 | drvrFlags
  .short 0x0000                                 | drvrDelay
  .short 0x0000                                 | drvrEMask
  .short 0x0000                                 | drvrMenu
  .short 0x0024                                 | drvrOpen
  .short 0x0028                                 | drvrPrime
  .short 0x002C                                 | drvrCtl
  .short 0x0030                                 | drvrStatus
  .short 0x0034                                 | drvrClose
  .byte 0x06                                    | drvrName length
  .byte 0x2E,0x50,0x72,0x69,0x6E,0x74           | drvrName: ".Print"
  .byte 0x20                                    | align to word
  .byte 0x00                                    | flags byte (unused)
  .byte 0x00                                    | pad byte
  .byte 0x44                                    | 'D' (resource type 'DRVR')
  .byte 0x52                                    | 'R'
  .byte 0x56                                    | 'V'
  .byte 0x52                                    | 'R'
  .byte 0x00                                    | resource ID high byte
  .byte 0x02                                    | resource ID = 2
  .byte 0x00                                    | version high byte
  .byte 0x19                                    | version = 25
| drvrOpen: offset $08 into PRER resource
PRINT_OPEN:
        MOVEQ.L #0x8,D1                         | PRER offset for Open
        BRA.B   PRINT_LOAD_PRER                 | -> load and jump
| drvrPrime: offset $0A
PRINT_PRIME:
        MOVEQ.L #0xA,D1                         | PRER offset for Prime (Read/Write)
        BRA.B   PRINT_LOAD_PRER                 | -> load and jump
| drvrCtl: offset $0C
PRINT_CTL:
        MOVEQ.L #0xC,D1                         | PRER offset for Control
        BRA.B   PRINT_LOAD_PRER                 | -> load and jump
| drvrStatus: offset $0E
PRINT_STATUS:
        MOVEQ.L #0xE,D1                         | PRER offset for Status
        BRA.B   PRINT_LOAD_PRER                 | -> load and jump
| drvrClose: offset $10
PRINT_CLOSE:
        MOVEQ.L #0x10,D1                        | PRER offset for Close
        NOP                                     | pad to match BRA.B instruction size
| PRINT_LOAD_PRER: load printer driver resource and dispatch
| D1 = offset into PRER to jump to, A0 = IOParam, A1 = DCE
PRINT_LOAD_PRER:
        SUBQ.W  #0x4,SP                         | space for return value
        MOVEM.L A0-A1,-(SP)                     | save IOParam and DCE
        MOVE    D1,-(SP)                        | save PRER offset
        MOVE    (CurMap).w,-(SP)                | save current resource map
        MOVE.L  A1,-(SP)                        | save DCE
| make the top map current: search all open resource files
        MOVE.L  (TopMapHndl).w,A0               | top of resource chain
        MOVE.L  (A0),A0                         | dereference
        MOVE    0x14(A0),(CurMap).w             | CurMap := top map's refNum (mRefNum, +$14)
| get printer driver filename from STR# -8192 resource
        SUBQ.W  #0x4,SP                         | space for handle result
        MOVE    #-0x2000,-(SP)                  | resource ID -8192 ($E000)
        _GetString                              | get printer driver name
        MOVE.L  (SP)+,A2                        | A2 = string handle
        BSET    #0x7,(A2)                       | lock the handle
        MOVE.L  (A2),A1                         | A1 = printer driver name string
| find the printer driver file on boot volume
        BSR     PRINT_GET_VREFNUM               | search for file
        MOVE    D0,-(SP)                        | save VRefNum
        MOVE    (BootDrive).w,D0                | boot volume
        BSR     PRINT_SET_VOL                   | look up volume name
| open the printer driver resource file
        SUBQ.W  #0x2,SP                         | space for refNum result
        MOVE.L  A1,-(SP)                        | push filename
        _OpenResFile                            | open printer driver resource fork
        MOVE.L  A2,-(SP)                        | push string handle
        _ReleaseResource                        | free the driver name string handle
        TST     (SP)+                           | check OpenResFile result and pop refNum
        BMI     PRINT_OPEN_FAILED               | if negative, file open failed ->
        MOVE    (SP)+,D0                        | pop saved VRefNum
        BSR     PRINT_SET_VOL                   | restore original volume
        SUBQ.W  #0x4,SP                         | space for resource handle result
        MOVE.L  #0x44525652,-(SP)               | 'DRVR' resource type
        MOVE    #-0x2000,-(SP)                  | resource ID -8192 ($E000)
        _GetResource                            | load driver resource from printer file
| check if PRER resource was found
        MOVE.L  (SP)+,D0                        | D0 = PRER resource handle
        BEQ     PRINT_ERR_EXIT                  | not found ->
        MOVE.L  D0,A2                           | A2 = PRER handle
        MOVE    (ResErr).w,D0                   | check resource error
        BMI     PRINT_ERR_EXIT                  | error ->
| detach resource so it persists after CloseResFile
        MOVE.L  A2,-(SP)                        | push PRER handle
        _DetachResource                         | detach from resource chain
| verify printer driver file exists on expected volume
        BSR     PRINT_CHK_DRVR                  | check printer driver file
        BNE.B   PRINT_INSTALL_PRER              | found ->
        MOVE    #-0xC0,D0                       | prNotFound (-192)
        BRA.B   PRINT_ERR_EXIT                  | -> error exit
| install PRER as the printer driver in the DCE
PRINT_INSTALL_PRER:
        MOVE.L  A2,0x8(A3)                      | RHndl (+8) of DRVR 2's System-map entry := PRER handle
        MOVE.L  (SP)+,A0                        | A0 = DCE pointer
        MOVE.L  (A2),A1                         | A1 = dereferenced PRER code
        MOVE.B  (A1),0x4(A0)                    | copy driver flags from PRER header
        BSET    #0x6,0x5(A0)                    | set dRAMBased flag in DCE
        MOVE.L  A2,(A0)                         | store PRER handle as driver pointer
| restore saved state and jump to PRER entry point
        MOVE    (SP)+,(CurMap).w                | restore resource map
        MOVE    (SP)+,D1                        | D1 = PRER offset for this entry
        BSET    #0x7,(A2)                       | lock PRER handle
        MOVE.L  (A2),A0                         | A0 = dereferenced PRER
        MOVE    0x0(A0,D1.W),D1                 | D1 = handler offset within PRER
        LEA.L   0x0(A0,D1.W),A0                 | A0 = handler address
        MOVE.L  A0,0x8(SP)                      | store as return address
        MOVEM.L (SP)+,A0-A1                     | restore IOParam and DCE
        RTS                                     | jump to PRER handler
| error: printer driver not found on this volume
PRINT_OPEN_FAILED:
        MOVE    (SP)+,D0                        | pop saved VRefNum
        BSR     PRINT_SET_VOL                   | restore volume
        MOVE    #-0xC1,D0                       | prIOErr (-193)
| common error exit: store error and return to caller
PRINT_ERR_EXIT:
        MOVE    D0,(PrintErr).w                 | save print error code
        MOVE.L  (SP)+,A0                        | pop saved DCE (discarded)
        MOVE    (SP)+,(CurMap).w                | restore resource map
        MOVE    (SP)+,D1                        | pop PRER offset
        MOVEM.L (SP)+,A0-A1                     | restore IOParam and DCE
        ADDQ.W  #0x4,SP                         | pop the 4-byte slot reserved at entry (SUBQ #4,SP)
| immediate call: plain RTS, otherwise return through IODone
        BTST    #0x9,0x6(A0)                    | immediate? (noQueueBit 9 of ioTrap)
        BNE.B   PRINT_RTS                       | yes ->
        MOVE.L  (JIODone).w,-(SP)               | push JIODone to return via IO completion
PRINT_RTS:
        RTS                                     | jump to JIODone (or return to caller)

| ----------------------------------------------------------
|
| PRINT_GET_VREFNUM
|
| PRINT_GET_VREFNUM: get current volume VRefNum (returns in D0)
PRINT_GET_VREFNUM:
        MOVEQ.L #0x0,D0                         | D0 = 0 (use default volume)
| PRINT_SET_VOL: set volume to D0, then get current volume back
PRINT_SET_VOL:
        SUBA    #0x40,SP                        | allocate param block on stack
        MOVE.L  A7,A0                           | A0 = param block
        MOVE    D0,0x16(A0)                     | ioVRefNum = D0
        CLR.L   0x12(A0)                        | ioNamePtr = nil
        _SetVol                                 | set default volume
        _GetVol                                 | get back actual VRefNum
        MOVE    0x16(A0),D0                     | D0 = returned VRefNum
        ADDA    #0x40,SP                        | deallocate param block
        RTS                                     | return with VRefNum in D0

| ----------------------------------------------------------
|
| PRINT_CHK_DRVR: check if printer driver DRVR 2 exists in System file
| Returns NE if found, EQ if not
|
PRINT_CHK_DRVR:
        MOVEM.L D0-D1/A1-A2,-(SP)               | save regs
        MOVE    (ResLoad).w,A1                  | save ResLoad state
        CLR     (ResLoad).w                     | disable auto-loading (just check)
        SUBQ.W  #0x4,SP                         | space for handle
        MOVE.L  #0x44525652,-(SP)               | 'DRVR' resource type
        MOVE    #0x2,-(SP)                      | DRVR ID 2 (.Print)
        _GetResource                            | check if it exists
        MOVE.L  (SP)+,D0                        | D0 = handle (or nil)
        BEQ.B   PRINT_CHK_NOTFOUND              | not found ->
| verify it's in the System file (not app)
        SUBQ.W  #0x4,SP                         | space for RsrcMapEntry result
        MOVE.L  D0,-(SP)                        | push resource handle
        _RsrcMapEntry                           | get resource map entry
        MOVE.L  (SP)+,D0                        | D0 = map entry (or 0)
        BEQ.B   PRINT_CHK_NOTFOUND              | not found ->
        MOVE.L  (SysMapHndl).w,A0               | A0 = System file map handle
        MOVE.L  (A0),D1                         | D1 = dereferenced System map
        ADD.L   D1,D0                           | make absolute address
PRINT_CHK_NOTFOUND:
        MOVE.L  D0,A3                           | A3 = resource map entry (or nil)
        MOVEM   A1,(ResLoad).w                  | restore ResLoad state
        MOVEM.L (SP)+,D0-D1/A1-A2               | restore regs
        RTS                                     | return (Z set if not found)

| end of resource : 'DRVR' 2 '.Print'

