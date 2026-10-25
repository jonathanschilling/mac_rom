| SCSI boot support -- CheckSCSI, SCSIProbeDevice, SCSIReadBlocks
|
| Apple source: SCSIBoot.a (MacSEROM.lst module SCSIBOOTS). Called while
| the system starts up: probes SCSI IDs 6 down to 0, reads each device's
| block 0 (the driver descriptor map, signature 'ER'), loads the first
| driver of type 1 into the system heap and calls its entry with block 1
| in A0; the driver installs itself, so that the disk joins the drive
| queue.
| Two ROM-variant sites are here (CheckSCSI, $7D44 and $7D4A).
|
| References: Inside Macintosh Vol IV, Ch 31: The SCSI Manager
| (driver descriptor map, partition map)

| ----------------------------------------------------------
|
| Check SCSI
|
| Called during boot.
CheckSCSI:
        TST.B   (HWCfgFlags).w                  | check hardware config flags
| --- ROM-variant difference @ $7D44 ---
| v1: BEQ.B SCSI_EXIT -- branched when HWCfgFlags == 0.
| v2/v3: BPL.B SCSI_EXIT -- branches when bit-7 (hasSCSI) is clear.
| Reason: v1's BEQ tested the whole byte instead of the hasSCSI flag
| bit, so a machine with SCSI present plus any other flag bit
| set would incorrectly skip the probe. v2 fixed this with BPL.
.if ROM_TARGET == MAC_PLUS_V1
        BEQ.B   SCSI_EXIT                       | Plus v1: skip when HWCfgFlags==0 (buggy)
.else
        BPL.B   SCSI_EXIT                       | Plus v2/v3: skip when hasSCSI bit clear
.endif
        MOVEM.L D0-D7/A0-A6,-(SP)               | save all registers
| --- ROM-variant difference @ $7D4A-$7D4D ---
| v1/v2: inline SCSI reset here -- `CLR.W -(SP); _SCSIDispatch` pushes the
| SCSIReset selector and calls the SCSI Manager.
| v3: two NOPs -- the reset now happens only from the extra-area SCSI
| patch (EXTRA_CONT in src/extra/extra.s), not here.
| Reason: same factoring that redirected InitIOMgr at $08AC; avoids
| doing the reset twice during boot.
.if ROM_TARGET < MAC_PLUS_V3
        CLR     -(SP)                           | Plus v1/v2: push selector 0 = SCSIReset
        _SCSIDispatch                           | Plus v1/v2: reset SCSI bus
.else
        NOP                                     | Plus v3: (reset moved to extra-area patch)
        NOP                                     | Plus v3: (reset moved to extra-area patch)
.endif
        MOVEQ.L #0x6,D5                         | D5 = 6: start from SCSI ID 6 (scan down to 0)
SCSI_PROBE_LOOP:
        BTst    D5,(SCSIDrvrs).w                | already found a driver at this ID?
        BNE.B   SCSI_NEXT_ID                    | yes: skip (already installed)
        BSR.B   SCSIProbeDevice                 | probe SCSI device at ID D5
SCSI_NEXT_ID:
        SUBQ.W  #0x1,D5                         | next lower SCSI ID
        BGE.B   SCSI_PROBE_LOOP                 | loop until all IDs 6..0 checked
        MOVEM.L (SP)+,D0-D7/A0-A6               | restore all registers
SCSI_EXIT:
        RTS                                     | return from CheckSCSI

| ----------------------------------------------------------
|
| SCSIProbeDevice
|
| Called during boot.
SCSIProbeDevice:                                | probe SCSI device at ID in D5
        SUBA.L  #0x100,SP                       | allocate 256 bytes on stack for read buffer
        MOVE.L  A7,A2                           | A2 = stack buffer (destination for reads)
        MOVEQ.L #0x0,D3                         | D3 = block 0 (read device descriptor map)
        MOVEQ.L #0x1,D2                         | D2 = 1 block to read
        MOVE    #0x100,D4                       | D4 = 256 bytes per block
        BSR.B   SCSIReadBlocks                  | Read block 0 from SCSI device
        BNE.B   SCSI_PROBE_EXIT                 | Read failed: no SCSI disk
        CMPI    #0x4552,(SP)                    | driver descriptor map signature (sbSig) 'ER'?
        BNE.B   SCSI_PROBE_EXIT                 | no: not a Macintosh SCSI disk
        MOVE    0x2(SP),D4                      | D4 = device block size (sbBlkSize)
        MOVE    0x10(SP),D0                     | D0 = number of drivers (sbDrvrCount)
        LEA.L   0x12(SP),A0                     | A0 = first driver descriptor
        MOVE.L  0xC(SP),D7                      | D7 = sbData (reserved long)
SCSI_FIND_DRVR:
        CMPI    #0x1,0x6(A0)                    | driver type (ddType) 1 = Macintosh driver?
        BEQ.B   SCSI_LOAD_DRVR                  | yes: load it
        ADDQ.L  #0x8,A0                         | next descriptor (8 bytes)
        SUBQ.W  #0x1,D0                         | More entries?
        BNE.B   SCSI_FIND_DRVR                  | more descriptors -> check the next
        BRA.B   SCSI_PROBE_EXIT                 | none of type 1: no driver

| ----------------------------------------------------------
|
| SCSI_LOAD_DRVR
|
SCSI_LOAD_DRVR:
        BSet    D5,(SCSIDrvrs).w                | Mark this SCSI ID as having a driver
        MOVE.L  (A0),D3                         | D3 = driver's first block (ddBlock)
        MOVE    0x4(A0),D2                      | D2 = its size in blocks (ddSize)
        MOVE.L  D4,D0                           | D0 = block size
        MULU    D2,D0                           | D0 = total driver size in bytes
        _NewPtrSys                              | Allocate memory for SCSI driver code
        MOVE.L  A0,A3                           | A3 = driver code buffer
        MOVE.L  A0,A2                           | A2 = buffer for reading driver
        BSR.B   SCSIReadBlocks                  | Read SCSI driver from disk into buffer
        BNE.B   SCSI_PROBE_EXIT                 | Read failed: abort
        MOVEQ.L #0x1,D3                         | D3 = block 1
        MOVEQ.L #0x1,D2                         | D2 = 1 block
        MOVE    #0x100,D4                       | D4 = 256 bytes
        MOVE.L  A7,A2                           | A2 = stack buffer for re-reading partition map
        BSR.B   SCSIReadBlocks                  | read block 1 into the stack buffer
        BNE.B   SCSI_PROBE_EXIT                 | Failed: abort
        MOVE.L  A2,A0                           | A0 = block 1 data (passed to the driver)
        JSR     (A3)                            | Execute loaded SCSI driver init routine (installs driver in Unit Table)
SCSI_PROBE_EXIT:
        ADDA    #0x100,SP                       | Clean up 256-byte stack allocation
        RTS                                     | Return from CheckSCSI

| ----------------------------------------------------------
|
| SCSIReadBlocks
|
| Called during boot.
SCSIReadBlocks:
        LEA.L   (scratch8).w,A0                 | A0 -> scratch8 (SCSI command block buffer)
        MOVE.B  #0x8,(A0)+                      | SCSI opcode = 8 (READ)
        SWAP    D3                              | Swap D3 to get high word (LUN + LBA high)
        ANDI.B  #0x1F,D3                        | Mask LBA high bits (5 bits)
        MOVE.B  D3,(A0)+                        | Store LUN + LBA high byte
        SWAP    D3                              | Swap back, store LBA low word
        MOVE    D3,(A0)+                        | Store LBA middle bytes
        MOVE.B  D2,(A0)+                        | Store block count
        CLR.B   (A0)+                           | Control byte = 0
        MULU    D2,D4                           | D4 = total transfer size (blocks * block size)
        SUBA    #0x14,SP                        | Allocate 20 bytes on stack for TIB (Transfer Instruction Block)
        MOVE.L  A7,D6                           | D6 = TIB pointer (save for SCSIRead)
        SUBQ.W  #0x2,SP                         | Make room for SCSIGet result
        MOVE    #0x1,-(SP)                      | Push selector = 1
        _SCSIDispatch                           | _SCSIDispatch(SCSIGet): arbitrate for SCSI bus
        TST     (SP)                            | Check result
        BNE.B   SCSI_READ_ERR                   | Error: clean up and return
        MOVE    D5,-(SP)                        | Push SCSI target ID
        MOVE    #0x2,-(SP)                      | Push selector = 2
        _SCSIDispatch                           | _SCSIDispatch(SCSISelect): select target device by SCSI ID
        TST     (SP)                            | Check result
        BNE.B   SCSI_READ_ERR                   | Error: clean up and return
        PEA.L   (scratch8).w                    | Push command block address (scratch8)
        MOVE    #0x6,-(SP)                      | Push command length = 6
        MOVE    #0x3,-(SP)                      | Push selector = 3
        _SCSIDispatch                           | _SCSIDispatch(SCSICmd): send 6-byte SCSI READ command
        TST     (SP)                            | Check result
        BNE.B   SCSI_READ_ERR                   | Error: clean up and return
        MOVE.L  D6,A0                           | A0 = TIB buffer on stack
        MOVE    #0x1,(A0)+                      | TIB opcode 1 = scInc (transfer with auto-increment)
        MOVE.L  A2,(A0)+                        | TIB buffer = read destination address
        MOVE.L  D4,(A0)+                        | TIB count = total bytes to transfer
        MOVE    #0x7,(A0)+                      | TIB terminator 7 = scStop (end of transfer list)
        MOVE.L  D6,-(SP)                        | Push TIB pointer for SCSIRead
        MOVE    #0x5,-(SP)                      | Push selector = 5
        _SCSIDispatch                           | _SCSIDispatch(SCSIRead): execute TIB-based data transfer
        PEA.L   (scratch8).w                    | Push status buffer address
        PEA.L   (scratch8_2).w                  | Push message buffer address
        MOVE.L  #0x3C,-(SP)                     | Push timeout = 60 ticks
        MOVE    #0x4,-(SP)                      | Push selector = 4
        _SCSIDispatch                           | _SCSIDispatch(SCSIComplete): get status/message, release bus
        TST     (SP)                            | Check result
        BNE.B   SCSI_READ_ERR                   | Error: clean up and return
        ADDQ.L  #0x2,SP                         | Clean SCSIComplete result from stack
        ADDA    #0x14,SP                        | Clean TIB from stack
        MOVEQ.L #0x0,D0                         | D0 = noErr
        RTS                                     | Return success

| ----------------------------------------------------------
|
| SCSI_READ_ERR
|
| Called during boot.
SCSI_READ_ERR:
        ADDQ.L  #0x2,SP                         | Clean result from stack
        ADDA    #0x14,SP                        | Clean TIB from stack
        MOVEQ.L #-0x1,D0                        | D0 = -1 (error)
        RTS                                     | Return error

