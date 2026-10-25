| SCSI boot support -- SCSILOAD
|
| Apple source: SCSIBoot.a (MacSEROM.lst module SCSIBOOTS). Called while
| the system starts up: probes the SCSI IDs, reads each device's driver
| descriptor map and partition map, loads the device driver into the
| system heap and opens it, so that SCSI disks join the drive queue.
|
| References: Inside Macintosh Vol IV, Ch 31 (The SCSI Manager)

| ====================================================================
|
| SCSILOAD -- scan SCSI bus for bootable HFS partitions
|
| Called from boot. Walks SCSI IDs 0..7 (skipping host ID and any
| ID whose driver is already installed), reads the partition map
| from each candidate device, and installs the .Apple_Driver /
| .Apple_HFS partition driver if found. Returns D0 = 0 if any
| driver was installed, else preserves the input mask in D0.
|
| Side effects: SCSIDrvrs bitmap updated for any IDs that now
| have a partition driver installed.
|
| Apple source module: SCSIBOOTS
SCSILOAD:
    BTST        #0x7,(HWCfgFlags)               | SCSI hardware present ?
    BNE.B       BOOT_SCSI_TRY_DRIVE             | yes, scan bus
    MOVEQ.L     #0x0,D0                         | no, return 0
    RTS                                         | return from SCSIBoots
BOOT_SCSI_TRY_DRIVE:
    MOVEM.L     D1-D7/A0-A6,-(A7)               | save all regs
    MOVE.B      D0,-(A7)                        | save input mask on stack
    MOVEQ.L     #0x7,D5                         | D5 = SCSI ID 7 (loop high to low)
BOOT_SCSI_DRIVE_OK:
    BTST        D5,(A7)                         | this ID enabled in mask ?
    BEQ.B       BOOT_SCSI_NO_DRIVE              | no, skip
    BTST        D5,(SCSIDrvrs)                  | already has a driver ?
    BNE.B       BOOT_SCSI_NO_DRIVE              | yes, skip
    BSR.B       BOOT_SCSI_SCAN_PMAP             | try to install partition driver
    BEQ.B       BOOT_SCSI_NO_DRIVE              | failed, leave mask bit set
    BCLR        D5,(A7)                         | succeeded, clear mask bit
BOOT_SCSI_NO_DRIVE:
    DBF.W       D5,BOOT_SCSI_DRIVE_OK           | next ID
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.B      (A7)+,D0                        | D0 = remaining (unbooted) IDs
    MOVEM.L     (A7)+,D1-D7/A0-A6               | restore regs
    TST.W       D0                              | set Z if all IDs booted
    RTS                                         | return from SCSIBoots
| ====================================================================
|
| BOOT_SCSI_SCAN_PMAP -- scan one SCSI device for a partition driver
|
| D5 = SCSI ID being probed.  Returns Z if a driver was loaded.
|
| Flow:
|   1. Read block 0 (Driver Descriptor Map). Check for "ER" signature
|      (0x4552). The DDM lists driver entries (8 bytes each: blockStart
|      blockCount type) for each driver embedded on the disk.
|   2. Walk DDM entries looking for type 1 (= Macintosh driver entry).
|   3. If found, allocate a sysHeap buffer big enough for the driver
|      blocks, read them in, and run the driver-init at offset 0.
|   4. The init code falls through into a partition-map scan: read
|      block 1 (PM signature = "PM" = 0x504D), walk partitions for
|      "Apple_Driver" / "Apple_HFS" entries, install each.
|
| Stack frame locals (relative to A6):
|   -4   L  driverBlockStart
|   -8   L  driverBlockCount
|   -10  L  partition map total entries
|   -16  L  partition map current index
|
BOOT_SCSI_SCAN_PMAP:
    LINK        A6,#-0x210                      | reserve 528 bytes (sector + locals)
    MOVEA.L     A7,A2                           | A2 -> sector buffer (on stack)
    MOVEQ.L     #0x0,D3                         | D3 = block 0 (DDM)
    MOVEQ.L     #0x1,D2                         | D2 = 1 block to read
    MOVE.W      #0x200,D4                       | D4 = 512 bytes per block
    BSR.W       SCSIREADBLOCKS                  | read DDM into buffer
    BNE.W       BOOT_SCSI_RUN_DRIVER            | read failed -> just return 0
    CMPI.W      #0x4552,(A7)                    | DDM signature "ER" ?
    BNE.B       BOOT_SCSI_RTS_ERR               | no, not a Mac partitioned disk
    MOVE.W      0x2(A7),D4                      | D4 = block size from DDM (sbBlkSize)
    MOVE.W      0x10(A7),D0                     | D0 = sbDrvrCount (driver entry count)
    BEQ.B       BOOT_SCSI_RTS_ERR               | no drivers, bail
    LEA.L       0x12(A7),A0                     | A0 -> first driver entry (DDM+18)
    MOVE.L      0xC(A7),D7                      | D7 = sbBlkCount (total disk blocks)
| Walk DDM driver entries (8 bytes each: ddBlock,ddSize,ddType)
SCSI_FIND_DRVR:
    CMPI.W      #0x1,0x6(A0)                    | ddType == 1 (Mac driver) ?
    BEQ.B       SCSI_LOAD_DRVR                  | yes, found it
    ADDQ.L      #0x8,A0                         | next entry
    SUBQ.L      #0x1,D0                         | dec entry counter
    BNE.B       SCSI_FIND_DRVR                  | more, keep looking
    BRA.B       BOOT_SCSI_RTS_ERR               | exhausted, bail
| Found a driver entry: load + execute it
SCSI_LOAD_DRVR:
    BSET        D5,(SCSIDrvrs)                  | mark this SCSI ID as having a driver
    MOVE.L      (A0),D3                         | D3 = ddBlock (driver start block)
    MOVE.L      D3,-0x4(A6)                     | save in driverBlockStart
    MOVEQ.L     #0x0,D2                         | clear D2
    MOVE.W      0x4(A0),D2                      | D2 = ddSize (driver block count)
    MOVE.L      D2,-0x8(A6)                     | save in driverBlockCount
    MOVE.L      D4,D0                           | D0 = block size
    MULU.W      D2,D0                           | * block count = byte size
    _NewPtrSys                                  | allocate sysHeap buffer
    BNE.B       BOOT_SCSI_RTS_ERR               | alloc failed, bail
    MOVEA.L     A0,A3                           | A3 -> driver buffer (saved for dispose)
    MOVEA.L     A0,A2                           | A2 -> read target
    BSR.W       SCSIREADBLOCKS                  | read driver blocks
    BNE.B       BOOT_SCSI_DISPOSE_BUF           | read failed, dispose + bail
    MOVEQ.L     #0x1,D3                         | D3 = block 1 (partition map)
    MOVE.L      D3,-0x10(A6)                    | save current PM index
    MOVEQ.L     #0x1,D2                         | D2 = 1 block
    MOVE.W      #0x200,D4                       | D4 = 512 bytes
    MOVEA.L     A7,A2                           | A2 -> sector buffer on stack
    BSR.W       SCSIREADBLOCKS                  | read partition map block 1
    BNE.B       BOOT_SCSI_DISPOSE_BUF           | read failed, dispose + bail
    CMPI.W      #0x5453,(A2)                    | "TS" signature (HFS first?)
    BEQ.B       BOOT_SCSI_NO_PMAP               | yes, just run driver init
    CMPI.W      #0x504D,(A2)                    | "PM" partition-map signature ?
    BNE.B       BOOT_SCSI_NO_PMAP               | no, run driver init anyway
    MOVE.L      0x4(A2),D0                      | D0 = pmMapBlkCnt (total PM entries)
    MOVE.L      D0,-0xC(A6)                     | save in -0xC(A6)
    BRA.B       BOOT_SCSI_PMAP_LOOP             | walk PM for driver/HFS entries
| BOOT_SCSI_NO_PMAP -- no partition map, just run the driver-init code
BOOT_SCSI_NO_PMAP:
    MOVEA.L     A2,A0                           | A0 -> sector buffer
    JSR         (A3)                            | call driver init at offset 0 of buffer
BOOT_SCSI_RUN_DRIVER:
    MOVEQ.L     #0x0,D0                         | D0 = 0 (success)
    BRA.B       BOOT_SCSI_RTS                   | unlink + return
| BOOT_SCSI_DISPOSE_BUF -- error path: dispose driver buffer, return -1
BOOT_SCSI_DISPOSE_BUF:
    MOVEA.L     A3,A0                           | A0 -> driver buffer
    _DisposePtr                                 | release sysHeap
BOOT_SCSI_RTS_ERR:
    MOVEQ.L     #-0x1,D0                        | D0 = -1 (no driver loaded)
BOOT_SCSI_RTS:
    UNLK        A6                              | release stack frame
    RTS                                         | return from BOOT_SCSI_SCAN_PMAP
| BOOT_SCSI_PMAP_LOOP -- check current PM entry for "Apple_Driver" partition.
| Partition entry layout (Apple Partition Map, 512 bytes):
|   +0x00 W  pmSig 0x504D ('PM')
|   +0x04 L  pmMapBlkCnt
|   +0x08 L  pmPyPartStart (physical block start)
|   +0x0C L  pmPartBlkCnt  (partition block count)
|   +0x10 ASCII pmPartName[32]   ("Macintosh" prefix matches here)
|   +0x30 ASCII pmParType[32]    ("Apple_Driver" / "Apple_HFS")
|   +0x60 L  pmLgDataStart (driver's logical start within partition)
|   +0x74 L  pmBootSize    (driver's expected size in bytes)
BOOT_SCSI_PMAP_LOOP:
    CMPI.L      #0x4170706C,0x30(A2)            | pmParType[0..3] = 'Appl' ?
    BNE.B       BOOT_SCSI_NEXT_PM_ENTRY         | no, next entry
    CMPI.L      #0x655F4472,0x34(A2)            | pmParType[4..7] = 'e_Dr' ?
    BNE.B       BOOT_SCSI_NEXT_PM_ENTRY         | no
    CMPI.L      #0x69766572,0x38(A2)            | pmParType[8..11] = 'iver' ?
    BNE.B       BOOT_SCSI_NEXT_PM_ENTRY         | no, ("Apple_Driver" mismatch)
    CMPI.L      #0x4D616369,0x10(A2)            | pmPartName[0..3] = 'Maci' ?
    BNE.B       BOOT_SCSI_NEXT_PM_ENTRY         | no, ("Macintosh" mismatch)
    MOVE.L      -0x4(A6),D0                     | D0 = our driverBlockStart
    CMP.L       0x8(A2),D0                      | match pmPyPartStart ?
    BNE.B       BOOT_SCSI_NEXT_PM_ENTRY         | no
    MOVE.L      -0x8(A6),D0                     | D0 = our driverBlockCount
    CMP.L       0xC(A2),D0                      | match pmPartBlkCnt ?
    BNE.B       BOOT_SCSI_NEXT_PM_ENTRY         | no
    MOVEA.L     A3,A0                           | A0 -> driver buffer
    MOVE.L      0x60(A2),D1                     | D1 = pmLgDataStart
    BSR.W       BOOT_SCSI_DRVR_REFNUM           | compute checksum over driver code
    CMP.L       0x74(A2),D0                     | match pmBootSize ?
    BEQ.B       BOOT_SCSI_RESCAN                | yes, install second-pass
    BRA.B       BOOT_SCSI_DISPOSE_BUF           | mismatch, dispose + bail
| BOOT_SCSI_NEXT_PM_ENTRY -- next PM entry (search continues for Apple_Driver)
| Called by: BOOT_SCSI_PMAP_LOOP, BOOT_SCSI_NEXT_PM_ENTRY
BOOT_SCSI_NEXT_PM_ENTRY:
    ADDQ.L      #0x1,-0x10(A6)                  | inc PM index
    MOVE.L      -0x10(A6),D3                    | D3 = current PM index
    CMP.L       -0xC(A6),D3                     | past last PM entry ?
    BHI.B       BOOT_SCSI_RESCAN                | yes, switch to HFS scan
    MOVEQ.L     #0x1,D2                         | D2 = 1 block
    MOVE.W      #0x200,D4                       | D4 = 512 bytes
    BSR.B       SCSIREADBLOCKS                  | read next PM block
    BNE.B       BOOT_SCSI_NEXT_PM_ENTRY         | read err, skip
    CMPI.W      #0x504D,(A2)                    | "PM" signature ?
    BNE.B       BOOT_SCSI_NEXT_PM_ENTRY         | no, skip
    BRA.B       BOOT_SCSI_PMAP_LOOP             | yes, check this entry
| BOOT_SCSI_RESCAN -- restart PM scan from block 1, look for Apple_HFS
BOOT_SCSI_RESCAN:
    MOVEQ.L     #0x0,D0                         | D0 = 0
    MOVE.L      D0,-0x10(A6)                    | reset PM index
| Called by: BOOT_SCSI_FIND_HFS
BOOT_SCSI_FIND_HFS:
    ADDQ.L      #0x1,-0x10(A6)                  | inc PM index
    MOVE.L      -0x10(A6),D3                    | D3 = current PM index
    CMP.L       -0xC(A6),D3                     | past last PM entry ?
    BHI.W       BOOT_SCSI_DISPOSE_BUF           | yes, dispose + bail
    MOVEQ.L     #0x1,D2                         | D2 = 1 block
    MOVE.W      #0x200,D4                       | D4 = 512 bytes
    BSR.B       SCSIREADBLOCKS                  | read next PM block
    BNE.B       BOOT_SCSI_FIND_HFS              | err, skip
    CMPI.W      #0x504D,(A2)                    | "PM" signature ?
    BNE.B       BOOT_SCSI_FIND_HFS              | no, skip
    CMPI.L      #0x4170706C,0x30(A2)            | pmParType[0..3] = 'Appl' ?
    BNE.B       BOOT_SCSI_FIND_HFS              | no
    CMPI.L      #0x655F4846,0x34(A2)            | pmParType[4..7] = 'e_HF' ?
    BNE.B       BOOT_SCSI_FIND_HFS              | no
    CMPI.B      #0x53,0x38(A2)                  | pmParType[8] = 'S' ?
    BNE.B       BOOT_SCSI_FIND_HFS              | no, ("Apple_HFS" mismatch)
    BRA.W       BOOT_SCSI_NO_PMAP               | yes, run driver init
| ====================================================================
|
| SCSIREADBLOCKS / SCSIReadBlocks -- read N blocks from a SCSI device
|
| D2 = block count, D3 = starting LBA, D4 = block size (bytes),
| D5 = SCSI ID, A2 -> destination buffer.
|
| Builds a 6-byte READ(6) command in (scratch8) and runs the
| selector sequence: SCSIGet (1) + SCSISelect (2) + CMP_COPY_FROM_DISK (3)
| + SCSIRead (5) + SCSIComplete (4). The first time around, if
| the target reports CHECK CONDITION (sense key == 6, unit
| attention), the routine retries once.
|
| Returns D7 = 0 on success.
|
| Called by: SCSI_LOAD_DRVR, BOOT_SCSI_SCAN_PMAP, BOOT_SCSI_NEXT_PM_ENTRY, BOOT_SCSI_FIND_HFS
SCSIREADBLOCKS:
    MOVE.L      D7,-(A7)                        | save D7
    MOVEQ.L     #0x0,D7                         | clear D7 (retry flag = 0)
| ----------------------------------------------------------
|
| SCSIReadBlocks
|
| Called during boot.
SCSIReadBlocks:
    LEA.L       (scratch8).W,A0                 | A0 -> CDB scratch (8 bytes)
    MOVE.B      #0x8,(A0)+                      | CDB[0] = 0x08 (READ(6))
    SWAP.W      D3                              | swap to read high half of LBA
    ANDI.B      #0x1F,D3                        | mask low 5 bits of LBA hi
    MOVE.B      D3,(A0)+                        | CDB[1] = LBA[20..16]
    SWAP.W      D3                              | swap back
    MOVE.W      D3,(A0)+                        | CDB[2..3] = LBA[15..0]
    MOVE.B      D2,(A0)+                        | CDB[4] = block count
    CLR.B       (A0)+                           | CDB[5] = control byte (0)
    MULU.W      D2,D4                           | D4 = total transfer bytes
    SUBA.W      #0x14,A7                        | reserve 20 bytes on stack for results
    MOVE.L      A7,D6                           | D6 = scratch result area
    SUBQ.L      #0x2,A7                         | reserve 2 bytes for SCSIDispatch result
    MOVE.W      #0x1,-(A7)                      | selector 1 = SCSIGet
    _SCSIDispatch                               | arbitrate for bus
    MOVE.W      (A7),D7                         | D7 = result word
    BNE.B       BOOT_SCSI_RDBLOCKS              | error -> bail
    MOVE.W      D5,-(A7)                        | push target SCSI ID
    MOVE.W      #0x2,-(A7)                      | selector 2 = SCSISelect
    _SCSIDispatch                               | select target
    MOVE.W      (A7),D7                         | D7 = result word
    BNE.W       BOOT_SCSI_RDBLOCKS              | error -> bail
    PEA.L       (scratch8).W                    | push CDB ptr
    MOVE.W      #0x6,-(A7)                      | CDB length = 6
    MOVE.W      #0x3,-(A7)                      | selector 3 = CMP_COPY_FROM_DISK
    _SCSIDispatch                               | send CDB
    MOVE.W      (A7),D7                         | D7 = result word
    BNE.B       BOOT_SCSI_HFS_FOUND             | error -> SCSIComplete then bail
    MOVEA.L     D6,A0                           | A0 -> result area
    MOVE.W      #0x1,(A0)+                      | TIB[0] = scInc
    MOVE.L      A2,(A0)+                        | TIB[1] = dst buffer ptr
    MOVE.L      D4,(A0)+                        | TIB[2] = byte count
    MOVE.W      #0x7,(A0)                       | TIB[3] = scStop
    MOVE.L      D6,-(A7)                        | push TIB ptr
    MOVE.W      #0x5,-(A7)                      | selector 5 = SCSIRead
    _SCSIDispatch                               | run TIB transfer
    MOVE.W      (A7),D7                         | D7 = result word
BOOT_SCSI_HFS_FOUND:
    PEA.L       (scratch8).W                    | push status buf
    PEA.L       (scratch8_2).W                  | push msg buf
    MOVE.L      #0x3C,-(A7)                     | timeout = 60 ticks
    MOVE.W      #0x4,-(A7)                      | selector 4 = SCSIComplete
    _SCSIDispatch                               | wait for completion
    TST.W       D7                              | last operation OK ?
    BNE.B       BOOT_SCSI_RDBLOCKS              | no, return its error
    MOVE.W      (A7),D7                         | D7 = SCSIComplete result
    CMPI.W      #0xA,D7                         | error == scComplPhaseErr (10) ?
    BNE.B       BOOT_SCSI_RDBLOCKS              | no, return whatever D7 is
    MOVE.W      (scratch8).W,D7                 | D7 = status byte (low) | sense
    BEQ.B       BOOT_SCSI_RDBLOCKS              | 0 = good, return success
    CMPI.W      #0x2,D7                         | CHECK CONDITION (status = 2) ?
    BNE.B       BOOT_SCSI_RDBLOCKS              | no, return error
    BSET        #0x1F,D7                        | yes, was bit 31 already set ?
    BEQ.W       SCSIReadBlocks                  | no, retry once
| Called by: BOOT_SCSI_HFS_FOUND, SCSIReadBlocks
BOOT_SCSI_RDBLOCKS:
    ADDA.W      #0x16,A7                        | drop 22 bytes of stack scratch
    MOVE.W      D7,D0                           | D0 = result code
    MOVE.L      (A7)+,D7                        | restore D7
    TST.W       D0                              | set Z if success
    RTS                                         | return from SCSIReadBlocks
| ----------------------------------------------------------
|
| BOOT_SCSI_DRVR_REFNUM -- 16-bit rotating-add checksum
|
| A0 -> data, D1 = byte count - 1.  For each byte:
|   D0 = ROL16(D0 + byte)
| Result in D0; if the natural result would be 0, returns -1
| instead so callers can use 0 as a sentinel.
|
BOOT_SCSI_DRVR_REFNUM:
    MOVEQ.L     #0x0,D0                         | sum = 0
    MOVEQ.L     #0x0,D7                         | clear high half of D7
    BRA.B       BOOT_SCSI_DRVR_OK               | enter loop test
BOOT_SCSI_DRVR_INSTALL:
    MOVE.B      (A0)+,D7                        | get next byte
    ADD.W       D7,D0                           | sum += byte
    ROL.W       #0x1,D0                         | rotate sum left 1 bit
BOOT_SCSI_DRVR_OK:
    DBF.W       D1,BOOT_SCSI_DRVR_INSTALL       | next byte
    TST.W       D0                              | result == 0 ?
    BNE.B       BOOT_SCSI_DRVR_RTS              | no, keep it
    SUBQ.W      #0x1,D0                         | yes, return -1 instead
BOOT_SCSI_DRVR_RTS:
    RTS                                         | return from BOOT_SCSI_DRVR_REFNUM
