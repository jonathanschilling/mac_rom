| -------------------------------------------------------------------------
| ROM tail after the last resource ($3CBA8-$3FFFF)
|
| Mac SE (1987): a 48-character string of developer initials,
| repeated up to $3FFED, then the build date "Thu, Nov 20, 1986" and a
| final $11 byte.
| Mac SE FDHD (1989): the same layout with the 12-character string
| "SWC JSP GGD ", but $3D000-$3DD51 holds the FDHD patch code: an entry
| table at $43D000 that the FDHD .Sony driver (jump table at $436BC6)
| and the RAM-test hook in boot/memtest.s ($43D034) jump into, followed
| by the patch routines; the date reads "Tue, Oct 11, 1988".
| -------------------------------------------------------------------------
| --- ROM-variant difference @ $3CBA8 ---
| SE:      initials "LWRLBBMABOEMTDAHJTCFJLMBKCRCLAKEHBRDCDAFSHFT JCS" (x278 + 38 chars), date 1986-11-20
| SE FDHD: initials "SWC JSP GGD ", FDHD patch code at $3D000, date 1988-10-11
| Reason: the SE FDHD put its patch code into the free tail space
.if ROM_TARGET == MAC_SE
ROMTail_Initials_SE:
    .rept       278
    .ascii      "LWRLBBMABOEMTDAHJTCFJLMBKCRCLAKEHBRDCDAFSHFT JCS"
    .endr
    .ascii      "LWRLBBMABOEMTDAHJTCFJLMBKCRCLAKEHBRDCD"
ROMTail_BuildDate_Thu_Nov_20_1986:
    .ascii      "Thu, Nov 20, 1986"             | build date
    .byte       0x11                            | last ROM byte
.else
| SE FDHD: the initials string from $3CBA8 up to the patch code at $3D000
ROMTail_Initials_FDHD:
    .rept       92
    .ascii      "SWC JSP GGD "
    .endr
    .ascii      "SWC JSP "

FDHD_ResourceTailPatchCode:
| =========================================================================
| SE FDHD .Sony driver, part 2: code in the free space at the end of the
| ROM ($3D000-$3DD51)
|
| The SuperDrive driver (part 1: resources/res_drvr_sony_fdhd.s) did not
| fit into the $2610-byte resource slot of the 1987 SE driver it replaces,
| so these routines were moved here, into the tail of the ROM, which is
| otherwise filled with the initials string. Driver and tail code call
| each other only through two fixed tables, with absolute addresses (the
| ROM runs at $400000):
|   driver -> tail: the driver's jump table SONY_TAIL_* ($436BC6) jumps to
|                   the entry table below ($43D000); the JRdAddr, JRdData
|                   and JSetUpPoll vectors point there too
|   tail -> driver: TAIL_DRV_* below jump to the driver's entry table
|                   SONY_DRVENT_* ($436C38), which branches to the routines
| Moved here: the GCR read routines (SetUpPoll, RdAddrSetup, RdAddr,
| RdData) with their tables, the GCR format and verify code (CtlFormat,
| SpdSeek, FormatTrack, DoFormat, FillInMarks, CtlVerify, VerTrack and
| the synchronous call helpers), and the icon/drive-info calls with the
| drive table and the four icons. Most of it is the 1987 SE driver's code
| with calls into the driver going through TAIL_DRV_*; RdAddr and RdData
| get an MFM test in front (mRdAddr/mRdData in the driver), CtlFormat and
| CtlVerify handle the MFM formats, the icon calls use the drvTblPtr
| (SonyVars+$178) indirection, and SuperDrives report drive type 4.
| The last entry is not part of the driver: the cold-start RAM test in
| boot/memtest.s jumps to it to touch all RAM banks before the test.
| =========================================================================
| Entry table: one BRA.W per routine, reached from the driver's jump
| table (entries 0-12) and from the RAM-test hook (entry 13, $43D034).
| -------------------------------------------------------------------------
TAILENT_RDADDR:
        BRA.W   Sony_RdAddr                     | 0: jtRdAddr (JRdAddr vector, via SONY_TAIL_RDADDR)
TAILENT_RDDATA:
        BRA.W   Sony_RdData                     | 1: jtRdData (JRdData vector, via SONY_TAIL_RDDATA)
TAILENT_SETUPPOLL:
        BRA.W   Sony_SetUpPoll                  | 2: jtSetUpPoll (JSetUpPoll vector, via SONY_TAIL_SETUPPOLL)
TAILENT_CTLFORMAT:
        BRA.W   Sony_CtlFormat                  | 3: CtlFormat (csCode 6, via SONY_TAIL_CTLFORMAT)
TAILENT_CTLVERIFY:
        BRA.W   Sony_CtlVerify                  | 4: CtlVerify (csCode 5, via SONY_TAIL_CTLVERIFY)
TAILENT_RDADDRSETUP:
        BRA.W   Sony_RdAddrSetup                | 5: RdAddrSetup (via SONY_TAIL_RDADDRSETUP)
TAILENT_READDATA:
        BRA.W   E_Sony_RdData                   | 6: RdData entry (via SONY_TAIL_READDATA)
TAILENT_TOEMPTYPD:
        BRA.W   SONY_TOEMPTYPD                  | 7: toEmptyPD (via SONY_TAIL_TOEMPTYPD)
TAILENT_E_SETUPPOLL:
        BRA.W   E_Sony_SetUpPoll                | 8: SetUpPoll entry (via SONY_TAIL_E_SETUPPOLL)
TAILENT_DRIVEICON:
        BRA.W   SONY_CTL_DRIVEICON              | 9: csCode 21, drive icon (via SONY_TAIL_DRIVEICON)
TAILENT_MEDIAICON:
        BRA.W   SONY_CTL_MEDIAICON              | 10: csCode 22, media icon (via SONY_TAIL_MEDIAICON)
TAILENT_DRVINFO:
        BRA.W   SONY_CTL_DRVINFO                | 11: csCode 23, drive info (via SONY_TAIL_DRVINFO)
TAILENT_SETDRVTBL:
        BRA.W   SONY_SETDRVTBL                  | 12: SetDrvTbl (DiskOpen, via SONY_TAIL_SETDRVTBL)
TAILENT_RAMTEST:
        BRA.W   FDHD_RAMTestPatch               | 13: RAM-test patch (JMP $43D034 in boot/memtest.s)

| -------------------------------------------------------------------------
| Jump table into the driver: absolute jumps to the driver's entry table
| SONY_DRVENT_* (one per routine the tail code calls)
| -------------------------------------------------------------------------
TAIL_DRV_ADRDISK:
        JMP     (SONY_DRVENT_ADRDISK-BASEOFROM+0x400000).l | AdrDisk
| Called by: E_Sony_RdAddr, E_Sony_RdData, SONY_CTLFORMAT_MARKS_2, SONY_CTLFORMAT_TRACKLOOP, SONY_CTLFORMAT_NEXT (and 5 more)
TAIL_DRV_GETDRV1:
        JMP     (SONY_DRVENT_GETDRV1-BASEOFROM+0x400000).l | GetDrv1
TAIL_DRV_MRDADDR:
        JMP     (SONY_DRVENT_MRDADDR-BASEOFROM+0x400000).l | mRdAddr
TAIL_DRV_DSKRTN:
        JMP     (SONY_DRVENT_DSKRTN-BASEOFROM+0x400000).l | DskRtn
TAIL_DRV_MRDDATA:
        JMP     (SONY_DRVENT_MRDDATA-BASEOFROM+0x400000).l | mRdData
TAIL_DRV_SETCHIPMODE:
        JMP     (SONY_DRVENT_SETCHIPMODE-BASEOFROM+0x400000).l | SetChipMode
TAIL_DRV_DISKSELECT:
        JMP     (SONY_DRVENT_DISKSELECT-BASEOFROM+0x400000).l | DiskSelect
TAIL_DRV_ADRANDSENSE:
        JMP     (SONY_DRVENT_ADRANDSENSE-BASEOFROM+0x400000).l | AdrAndSense
TAIL_DRV_MFMTTRACK:
        JMP     (SONY_DRVENT_MFMTTRACK-BASEOFROM+0x400000).l | mFmtTrack
TAIL_DRV_DSKRWOFF:
        JMP     (SONY_DRVENT_DSKRWOFF-BASEOFROM+0x400000).l | DskRWOff
TAIL_DRV_MVERTRACK:
        JMP     (SONY_DRVENT_MVERTRACK-BASEOFROM+0x400000).l | mVerTrack
TAIL_DRV_EMPTYPD:
        JMP     (SONY_DRVENT_EMPTYPD-BASEOFROM+0x400000).l | EmptyPD
TAIL_DRV_SEEK:
        JMP     (SONY_DRVENT_SEEK-BASEOFROM+0x400000).l | Seek
TAIL_DRV_RWPOWERUP:
        JMP     (SONY_DRVENT_RWPOWERUP-BASEOFROM+0x400000).l | RWPowerUp
TAIL_DRV_GETFREQ1:
        JMP     (SONY_DRVENT_GETFREQ1-BASEOFROM+0x400000).l | GetFreq1
| AdrMks (Apple's name) -- marks of a GCR address field: address mark
| $D5 $AA $96, bit slip marks $DE $AA (RdAddr compares these five; the $FF
| is not used). $D5 and $AA are reserved as mark bytes, no data nibble
| has these values (SWIM Chip User's Ref, "GCR Encoding").
DT_Sony_SectorAdrTbl:
        .byte   0xD5,0xAA,0x96,0xDE,0xAA,0xFF   | address mark $D5 $AA $96, slip marks $DE $AA, $FF

| -------------------------------------------------------------------------
| SetUpPoll -- prepare the SCC polling during disk I/O (through the
| JSetUpPoll vector): A6 = SCC channel A data (read), A5 = VIA port A
| (bit 7 = SCC W/REQ), interrupts off, PollStack = SP + D0. Now from the
| low-memory pointers SCCRd and VIA (1987 SE: absolute addresses).
| Received bytes are pushed on the stack and later handed to PollProc by
| EmptyPD.
|   D0 (in) -- bytes of return addresses on the stack (4 or 8): PollStack
|              = SP + D0, the caller's stack level once they are popped
|              (Apple: "compensate for 1 or 2 levels"); EmptyPD resets SP
|              to it when there is no PollProc
| -------------------------------------------------------------------------
E_Sony_SetUpPoll:
        MOVE.L  (DiskVars_JSetUpPoll).w,-(SP)   | push SetUpPoll vector address
        RTS                                     | dispatch to Sony_SetUpPoll
| jtSetUpPoll (JSetUpPoll vector)
Sony_SetUpPoll:
        MOVEA.L (SCCRd).w,A6                    | A6 = SCCRd (SCC read base)
        ADDQ.L  #0x6,A6                         | + 6: channel A data
        MOVEA.L (VIA).w,A5                      | A5 = VIA base
        ADDA.W  #0x1E00,A5                      | + $1E00: port A (vBufA)
        ORI     #0x300,SR                       | no interrupts from now on
        MOVE.L  SP,(PollStack).w                | PollStack = SP
        ADD.L   D0,(PollStack).w                | + D0 (the return addresses)
        RTS                                     | return from Sony_SetUpPoll

| -------------------------------------------------------------------------
| RdAddrSetup -- set up the polling, select the head of side SideTrack
| and read the next address mark (RdAddr: GCR or MFM)
|   D0, D1, D2, D3 (out) -- as RdAddr (D1 = side/track, D2 = sector,
|                           D3 = format byte)
| -------------------------------------------------------------------------
Sony_RdAddrSetup:
        MOVEQ.L #0x8,D0                         | PollStack = SP + 8 (two return addresses)
        BSR.B   E_Sony_SetUpPoll                | set up A5/A6 and PollStack
        MOVEQ.L #0x1,D0                         | RdDtaAdr (1): read data, head 0
        BTST    #0x3,SideTrack(A1)              | side 1 requested (bit 11 of SideTrack)?
        BEQ.B   SONY_RDADDRSETUP_SIDE           | no -> side 0
        MOVEQ.L #0x3,D0                         | RdDta1Adr (3): read data, head 1
SONY_RDADDRSETUP_SIDE:
        BSR.W   TAIL_DRV_ADRDISK                | AdrDisk: select the head
| RdAddr -- read the next address field: MFM disks with mRdAddr in the
| driver, GCR disks through the JRdAddr vector
E_Sony_RdAddr:
        BSR.W   TAIL_DRV_GETDRV1                | GetDrv1: A1, D1
        TST.B   mfmDisk(A1,D1.W)                | mfmDisk: MFM disk?
        BMI.W   TAIL_DRV_MRDADDR                | yes -> mRdAddr
SONY_RDADDR_GCR:
        LEA.L   DT_Sony_SectorAdrTbl(PC),A2     | A2 -> AdrMks: address mark table
        MOVE.L  (DiskVars_JRdAddr).w,-(SP)      | push the JRdAddr vector
        RTS                                     | and jump through it

| -------------------------------------------------------------------------
| jtRdAddr (JRdAddr vector) -- read the next address mark
|   A2 (in) -- address mark table, A5/A6 (in) -- VIA / SCC pointers
|   D0 (out) -- >= 0: nibbles left of the must-find count; or noNybErr
|               (-66), noAdrMkErr (-67), badCkSmErr (-69), badBtSlpErr
|               (-70)
|   D1 (out) -- side/track (track bits 0-10, side bit 11), D2 -- sector,
|               D3 -- format byte (Apple's source: "volume")
|   A3 (out) -- denibblize table - $96, A4 (out) -- IWM q6L
| The disk must be up to speed with the head selected, interrupts off.
| Address field (SWIM Chip User's Reference, GCR Track Format): marks $D5
| $AA $96, then as nibbles the track (bits 0-5), the sector, the side
| (bit 5) with track bits 6-10, the format byte and the checksum (XOR of
| the four), then the bit-slip marks $DE $AA. A byte read from q6L is
| valid when bit 7 is set (asynchronous latch mode). noNybErr: MTN #272
| says "could not find five nibbles in 200 tries"; this code wants 3
| nibbles within 128 reads.
| -------------------------------------------------------------------------
Sony_RdAddr:
        MOVEQ.L #0x3,D3                         | D3 = 3: find 3 nibbles first (Apple: "try for 3 bytes")
        MOVEQ.L #0x7F,D2                        | D2: within at most 128 reads of the data register
        MOVEQ.L #0x0,D5                         | D5 = 0: nibbles are used as a word index
        MOVEA.L (IWM).w,A4                      | A4 = IWM base (low-memory IWM)
        ADDA.W  #0x1800,A4                      | A4 -> q6L: data register (L6 = L7 = 0, motor on)
        MOVE.L  (SP)+,(DskRtnAdr).w             | save return address
| first find 3 nibbles (there is data on the track at all)
SONY_RDADDR_SKIP:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDADDR_CONT                | no SCC byte waiting ->
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDADDR_CONT:
        MOVE.B  (A4),D5                         | read byte from IWM data register
        DBF     D2,SONY_RDADDR_LOOP             | decrement timeout
        MOVEQ.L #-0x42,D0                       | noNybErr (-66): fewer than 3 nibbles in 128 reads
        BRA.W   SONY_RDADDRXIT                  | -> error exit
SONY_RDADDR_LOOP:
        BPL.B   SONY_RDADDR_SKIP                | bit 7 clear: not a valid disk byte
        SUBQ.W  #0x1,D3                         | one more nibble
        BNE.B   SONY_RDADDR_SKIP                | until 3 were seen (not necessarily in a row)
        MOVE    #0x5DC,D0                       | MustFindCt: find the mark within 1500 nibbles
        TST.B   NewIntf(A1,D1.W)                | NewIntf: 800K interface?
        BEQ.B   SONY_RDADDR_CONT_2              | 400K -> use $5DC timeout
        MOVE    #0x5BC,D0                       | new-interface drive: MustFindCt - 32
SONY_RDADDR_CONT_2:
        LEA.L   SONY_DENIBLTBL-0x96(PC),A3      | A3 -> denibblize table - $96 (indexed by disk byte)
SONY_RDADDR_CONT_3:
        MOVE.L  A2,A0                           | A0 -> address mark pattern $D5 $AA $96
        MOVEQ.L #0x3,D1                         | D1 = 3 header bytes to match
SONY_RDADDR_NEXT:
        MOVE.B  (A4),D5                         | read byte from IWM data register
        BPL.B   SONY_RDADDR_NEXT                | bit 7 clear: not valid, keep polling
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDADDR_SKIP_2              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDADDR_SKIP_2:
        DBF     D0,SONY_RDADDR_LOOP_2           | decrement scan timeout
        MOVEQ.L #-0x43,D0                       | noAdrMkErr (-67): no address mark within MustFindCt nibbles
        BRA.B   SONY_RDADDRXIT                  | return error
SONY_RDADDR_LOOP_2:
        CMP.B   (A0)+,D5                        | does disk byte match expected sync?
        BNE.B   SONY_RDADDR_CONT_3              | mismatch -> restart pattern scan
        SUBQ.W  #0x1,D1                         | decrement bytes remaining in pattern
        BNE.B   SONY_RDADDR_NEXT                | more bytes needed -> read next
SONY_RDADDR_CONT_4:
        MOVE.B  (A4),D5                         | read 1st addr field byte from disk
        BPL.B   SONY_RDADDR_CONT_4              | poll until valid disk byte
        MOVE.B  0x0(A3,D5.W),D1                 | GCR decode: low 6 bits of track
        MOVE.B  D1,D4                           | D4 = running checksum XOR
        ROR     #0x6,D1                         | park them in bits 10-15 (room for the side byte)
SONY_RDADDR_CONT_5:
        MOVE.B  (A4),D5                         | read 2nd addr field byte
        BPL.B   SONY_RDADDR_CONT_5              | poll until valid
        MOVE.B  0x0(A3,D5.W),D2                 | GCR decode: sector number
        EOR.B   D2,D4                           | accumulate into checksum
SONY_RDADDR_CONT_6:
        MOVE.B  (A4),D5                         | read 3rd addr field byte
        BPL.B   SONY_RDADDR_CONT_6              | poll until valid
        MOVE.B  0x0(A3,D5.W),D1                 | GCR decode: side (bit 5) and track bits 6-10
        EOR.B   D1,D4                           | accumulate into checksum
        ROL     #0x6,D1                         | D1 bits 0-11: side (bit 11) and track
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDADDR_SKIP_3              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDADDR_SKIP_3:
        MOVE.B  (A4),D5                         | read 4th addr field byte
        BPL.B   SONY_RDADDR_SKIP_3              | poll until valid
        MOVE.B  0x0(A3,D5.W),D3                 | GCR decode: format byte ($02/$22: 2:1 interleave, $20 = two-sided)
        EOR.B   D3,D4                           | accumulate into checksum
SONY_RDADDR_CONT_7:
        MOVE.B  (A4),D5                         | read 5th addr field byte (checksum)
        BPL.B   SONY_RDADDR_CONT_7              | poll until valid
        MOVE.B  0x0(A3,D5.W),D5                 | GCR decode: expected checksum
        EOR.B   D5,D4                           | XOR with accumulated: should be 0
        BNE.B   SONY_RDADDR_ERR_2               | nonzero -> checksum failed
        MOVEQ.L #0x1,D4                         | D4 = 1: expect 2 trailer bytes
SONY_RDADDR_LOOP_3:
        MOVE.B  (A4),D5                         | read trailer byte from disk
        BPL.B   SONY_RDADDR_LOOP_3              | poll until valid
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDADDR_SKIP_4              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDADDR_SKIP_4:
        CMP.B   (A0)+,D5                        | compare trailer against $DE, $AA
        BNE.B   SONY_RDADDR_ERR_3               | mismatch -> bad bit-slip error
        DBF     D4,SONY_RDADDR_LOOP_3           | read next trailer byte
| Branch from: SONY_RDADDR_CONT, SONY_RDADDR_SKIP_2, SONY_RDADDR_ERR_2, SONY_RDADDR_ERR_3, SONY_RDDATA_SKIP
SONY_RDADDRXIT:
        BRA.W   TAIL_DRV_DSKRTN                 | RdAddrXit: return through DskRtn (D0 >= 0: ok)
SONY_RDADDR_ERR_2:
        MOVEQ.L #-0x45,D0                       | badCkSmErr (-69): address field checksum wrong
        BRA.B   SONY_RDADDRXIT                  | abort and return error
SONY_RDADDR_ERR_3:
        MOVEQ.L #-0x46,D0                       | badBtSlpErr (-70): address field slip marks wrong
        BRA.B   SONY_RDADDRXIT                  | abort and return error
| DtaMks (Apple) -- marks of a GCR data field: data mark $D5 $AA $AD, bit
| slip marks $DE $AA (the $FF is not compared)
SONY_DTAMKS:
        .byte   0xD5,0xAA,0xAD,0xDE,0xAA,0xFF   | data mark $D5 $AA $AD, slip marks $DE $AA, $FF
| RdData -- read the data field after the address field just read: MFM
| disks with mRdData in the driver, GCR disks through the JRdData vector
E_Sony_RdData:
        BSR.W   TAIL_DRV_GETDRV1                | GetDrv1: A1, D1
        TST.B   mfmDisk(A1,D1.W)                | mfmDisk: MFM disk?
        BMI.W   TAIL_DRV_MRDDATA                | yes -> mRdData
SONY_RDDATA_GCR:
        LEA.L   SONY_DTAMKS(PC),A1              | A1 -> DtaMks: data mark table
        MOVE.L  (DiskVars_JRdData).w,-(SP)      | push RdData vector
        RTS                                     | jump to RdData implementation

| -------------------------------------------------------------------------
| jtRdData (JRdData vector) -- read the GCR data field of the sector whose
| address field was just read: data mark ($D5 $AA $AD), sector number
| (to TagData+1), then 524 bytes (12 tag bytes to TagData+2.., 512 data
| bytes to (A0)) encoded 6-and-2 with three running checksums, the
| checksum and the bit slip marks. With DskVerify set (read-verify) the
| data are compared with the buffer instead of being stored.
| Data field (SWIM Chip User's Ref, "GCR Track Format"): $D5 $AA $AD,
| sector number, 699 nibbles for the 524 bytes (174 groups of three
| bytes as four nibbles -- one with their top 2 bits each, three with
| their low 6 bits -- and a last group of two), 4 nibbles for the three
| checksum bytes, then the slip marks $DE $AA. Each byte is XORed with a
| running checksum before encoding (the algorithm is listed there).
|   A0 (in) -- data buffer, A1 (in) -- DtaMks, A3/A4 (in) -- from RdAddr
|   D0 (out) -- 0 or noDtaMkErr (-71), badDCkSum (-72), badDBtSlp (-73),
|               dataVerErr (-68)
| -------------------------------------------------------------------------
Sony_RdData:
        MOVE.L  (SP)+,(DskRtnAdr).w             | save return address
        MOVEQ.L #0x30,D2                        | D2 = 48: find the data mark within 48 nibbles
        MOVEQ.L #0x0,D3                         | D3 = 0: nibbles are used as a word index
        MOVEQ.L #-0x40,D0                       | D0 = $C0: mask for bits 7-6 (MOVEQ #-64)
        MOVE.L  #0x1FE000A,D4                   | counts: lo 10 -> 4 groups = 12 tag bytes, hi $1FE -> 170 groups + 2 = 512 data bytes
        MOVEQ.L #0x0,D5                         | init CkSumA
        MOVEQ.L #0x0,D6                         | init CkSumB
        MOVEQ.L #0x0,D7                         | init CkSumC
SONY_RDDATA_CONT:
        MOVE.L  A1,A2                           | put header/trailer table pointer into A2
        MOVEQ.L #0x3,D1                         | D1 = 3 data mark bytes to match ($D5 $AA $AD)
SONY_RDDATA_LOOP:
        MOVE.B  (A4),D3                         | read a byte from disk
        BPL.B   SONY_RDDATA_LOOP                | no nibble yet -> read again
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP                | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP:
        DBF     D2,SONY_RDDATA_LOOP_2           | decrement timeout and loop
        MOVEQ.L #-0x47,D0                       | noDtaMkErr (-71): no data mark within 48 nibbles
        BRA.B   SONY_RDADDRXIT                  | abort and return error
SONY_RDDATA_LOOP_2:
        CMP.B   (A2)+,D3                        | compare the disk byte against the expected header
        BNE.B   SONY_RDDATA_CONT                | header mismatch, restart scan
        SUBQ.W  #0x1,D1                         | one more mark byte matched
        BNE.B   SONY_RDDATA_LOOP                | loop if more mark bytes to match
SONY_RDDATA_CONT_2:
        MOVE.B  (A4),D3                         | read a byte from disk
        BPL.B   SONY_RDDATA_CONT_2              | no nibble yet -> read again
        LEA.L   (TagData_1).w,A1                | A1 -> TagData+1
        MOVE.B  0x0(A3,D3.W),(A1)+              | sector number of the data mark -> TagData+1
SONY_RDDATA_CONT_3:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_2              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_2:
        MOVE.B  (A4),D3                         | read a byte from disk
        BPL.B   SONY_RDDATA_CONT_3              | no nibble yet -> read again
        MOVE.B  0x0(A3,D3.W),D1                 | GCR decode: 6-bit nibble with 2+2+2 extra bits
        ROL.B   #0x2,D1                         | rotate extra bits into position
        MOVE.B  D1,D2                           | D2 = copy for masking low bits
        AND.B   D0,D2                           | D2 = bits 7-6 of byte A
SONY_RDDATA_CONT_4:
        MOVE.B  (A4),D3                         | read next GCR byte from disk
        BPL.B   SONY_RDDATA_CONT_4              | poll until valid
        OR.B    0x0(A3,D3.W),D2                 | combine decoded low 6 bits with high 2
        MOVE.B  D7,D3                           | D3 = previous checksum byte C
        ADD.B   D7,D3                           | X = bit 7 of checksum C
        ROL.B   #0x1,D7                         | rotate checksum C left (not through X)
        EOR.B   D7,D2                           | decrypt: XOR with running checksum
        MOVE.B  D2,(A1)+                        | store decoded tag/data byte A
        ADDX.B  D2,D5                           | accumulate checksum A into D5
        ROL.B   #0x2,D1                         | rotate next 2 extra bits into position
        MOVE.B  D1,D2                           | D2 = copy for masking
        AND.B   D0,D2                           | D2 = bits 7-6 of byte B
SONY_RDDATA_CONT_5:
        MOVE.B  (A4),D3                         | read next GCR byte from disk
        BPL.B   SONY_RDDATA_CONT_5              | poll until valid
        OR.B    0x0(A3,D3.W),D2                 | combine decoded low 6 with high 2
        EOR.B   D5,D2                           | decrypt: XOR with checksum D5
        MOVE.B  D2,(A1)+                        | store decoded byte B
        ADDX.B  D2,D6                           | accumulate checksum B into D6
        ROL.B   #0x2,D1                         | rotate last 2 extra bits into position
        AND.B   D0,D1                           | D1 = bits 7-6 of byte C
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_3              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_3:
        MOVE.B  (A4),D3                         | read next GCR byte from disk
        BPL.B   SONY_RDDATA_SKIP_3              | poll until valid
        OR.B    0x0(A3,D3.W),D1                 | combine decoded low 6 with high 2
        EOR.B   D6,D1                           | decrypt: XOR with checksum D6
        MOVE.B  D1,(A1)+                        | store decoded byte C
        ADDX.B  D1,D7                           | accumulate checksum C into D7
        SUBQ.W  #0x3,D4                         | decrement count of remaining bytes
        BPL.B   SONY_RDDATA_CONT_3              | more bytes in this buffer -> next group
        SWAP    D4                              | done with tag bytes
        TST.B   (DskVerify).w                   | read-verify (ioPosMode bit 6, DskVerify)?
        BEQ.B   SONY_RDDATA_SKIP_4              | no -> read data normally
        BRA.B   SONY_RDDATA_SKIP_6              | yes -> verify (compare) instead
SONY_RDDATA_LOOP_3:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_4              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_4:
        MOVE.B  (A4),D3                         | read GCR nibble byte from disk
        BPL.B   SONY_RDDATA_LOOP_3              | poll until valid disk byte
        MOVE.B  0x0(A3,D3.W),D1                 | GCR decode: nibble with 3x2 extra bits
        ROL.B   #0x2,D1                         | rotate first 2 extra bits
        MOVE.B  D1,D2                           | copy for masking
        AND.B   D0,D2                           | mask high 2 bits
SONY_RDDATA_CONT_6:
        MOVE.B  (A4),D3                         | read next GCR byte
        BPL.B   SONY_RDDATA_CONT_6              | poll until valid
        OR.B    0x0(A3,D3.W),D2                 | combine low 6 with high 2
        MOVE.B  D7,D3                           | D3 = checksum C
        ADD.B   D7,D3                           | X = bit 7 of checksum C
        ROL.B   #0x1,D7                         | rotate checksum C left (not through X)
        EOR.B   D7,D2                           | decrypt byte A via XOR
        MOVE.B  D2,(A0)+                        | store decoded data byte A
        ADDX.B  D2,D5                           | accumulate into checksum D5
        ROL.B   #0x2,D1                         | rotate next 2 extra bits
        MOVE.B  D1,D2                           | copy for masking
        AND.B   D0,D2                           | mask high 2 bits
SONY_RDDATA_CONT_7:
        MOVE.B  (A4),D3                         | read next GCR byte
        BPL.B   SONY_RDDATA_CONT_7              | poll until valid
        OR.B    0x0(A3,D3.W),D2                 | combine low 6 with high 2
        EOR.B   D5,D2                           | decrypt byte B via XOR
        MOVE.B  D2,(A0)+                        | store decoded data byte B
        ADDX.B  D2,D6                           | accumulate into checksum D6
        TST     D4                              | bytes remaining in sector?
        BEQ.B   SONY_RDDATA_DONE                | zero -> sector complete, check checksum
        ROL.B   #0x2,D1                         | rotate last 2 extra bits
        AND.B   D0,D1                           | mask high 2 bits
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_5              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_5:
        MOVE.B  (A4),D3                         | read next GCR byte
        BPL.B   SONY_RDDATA_SKIP_5              | poll until valid
        OR.B    0x0(A3,D3.W),D1                 | combine low 6 with high 2
        EOR.B   D6,D1                           | decrypt byte C via XOR
        MOVE.B  D1,(A0)+                        | store decoded data byte C
        ADDX.B  D1,D7                           | accumulate into checksum D7
        SUBQ.W  #0x3,D4                         | 3 bytes decoded per group
        BRA.B   SONY_RDDATA_LOOP_3              | loop for remaining data bytes
SONY_RDDATA_LOOP_4:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_6              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_6:
        MOVE.B  (A4),D3                         | read GCR nibble from disk (verify)
        BPL.B   SONY_RDDATA_LOOP_4              | poll until valid
        MOVE.B  0x0(A3,D3.W),D1                 | GCR decode: nibble with 3x2 extra bits
        ROL.B   #0x2,D1                         | rotate first 2 extra bits
        MOVE.B  D1,D2                           | copy for masking
        AND.B   D0,D2                           | mask high 2 bits
SONY_RDDATA_CONT_8:
        MOVE.B  (A4),D3                         | read next GCR byte
        BPL.B   SONY_RDDATA_CONT_8              | poll until valid
        OR.B    0x0(A3,D3.W),D2                 | combine low 6 with high 2
        MOVE.B  D7,D3                           | D3 = checksum C
        ADD.B   D7,D3                           | X = bit 7 of checksum C
        ROL.B   #0x1,D7                         | rotate checksum C left (not through X)
        EOR.B   D7,D2                           | decrypt byte A via XOR
        CMP.B   (A0)+,D2                        | compare decoded byte A with buffer
        BNE.B   SONY_RDDATA_ERR                 | mismatch -> verify error
        ADDX.B  D2,D5                           | accumulate checksum A
        ROL.B   #0x2,D1                         | rotate next 2 extra bits
        MOVE.B  D1,D2                           | copy for masking
        AND.B   D0,D2                           | mask high 2 bits
SONY_RDDATA_CONT_9:
        MOVE.B  (A4),D3                         | read next GCR byte
        BPL.B   SONY_RDDATA_CONT_9              | poll until valid
        OR.B    0x0(A3,D3.W),D2                 | combine low 6 with high 2
        EOR.B   D5,D2                           | decrypt byte B via XOR
        CMP.B   (A0)+,D2                        | compare decoded byte B with buffer
        BNE.B   SONY_RDDATA_ERR_3               | mismatch -> read-verify error
        ADDX.B  D2,D6                           | accumulate checksum B
        TST     D4                              | bytes remaining?
        BEQ.B   SONY_RDDATA_DONE                | zero -> done, check checksum
        ROL.B   #0x2,D1                         | rotate last 2 extra bits
        AND.B   D0,D1                           | mask high 2 bits
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_7              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_7:
        MOVE.B  (A4),D3                         | read next GCR byte (verify C)
        BPL.B   SONY_RDDATA_SKIP_7              | poll until valid
        OR.B    0x0(A3,D3.W),D1                 | combine low 6 with high 2
        EOR.B   D6,D1                           | decrypt byte C via XOR
        CMP.B   (A0)+,D1                        | compare decoded byte C with buffer
SONY_RDDATA_ERR:
        BNE.B   SONY_RDDATA_ERR_3               | mismatch -> read-verify error
        ADDX.B  D1,D7                           | accumulate checksum C
        SUBQ.W  #0x3,D4                         | 3 bytes verified per group
        BRA.B   SONY_RDDATA_LOOP_4              | loop for remaining verify bytes
SONY_RDDATA_DONE:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_8              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_8:
        MOVE.B  (A4),D3                         | read GCR checksum nibble byte
        BPL.B   SONY_RDDATA_SKIP_8              | poll until valid
        MOVE.B  0x0(A3,D3.W),D1                 | GCR decode: nibble with 4x2 cksum bits
        BMI.B   SONY_RDDATA_ERR_2               | $FF = invalid GCR byte
        ROL.B   #0x2,D1                         | rotate first 2 checksum bits
        MOVE.B  D1,D2                           | copy for masking
        AND.B   D0,D2                           | mask high 2 bits of checksum A
SONY_RDDATA_CONT_10:
        MOVE.B  (A4),D3                         | read checksum byte for D5
        BPL.B   SONY_RDDATA_CONT_10             | poll until valid
        MOVE.B  0x0(A3,D3.W),D3                 | GCR decode: low 6 checksum bits
        BMI.B   SONY_RDDATA_ERR_2               | invalid GCR byte -> error
        OR.B    D3,D2                           | D2 = full 8-bit checksum A
        CMP.B   D2,D5                           | compare with accumulated D5
        BNE.B   SONY_RDDATA_ERR_2               | mismatch -> checksum error
        ROL.B   #0x2,D1                         | rotate next 2 checksum bits
        MOVE.B  D1,D2                           | copy for masking
        AND.B   D0,D2                           | mask high 2 bits of checksum B
SONY_RDDATA_CONT_11:
        MOVE.B  (A4),D3                         | read checksum byte for D6
        BPL.B   SONY_RDDATA_CONT_11             | poll until valid
        MOVE.B  0x0(A3,D3.W),D3                 | GCR decode: low 6 checksum bits
        BMI.B   SONY_RDDATA_ERR_2               | invalid GCR byte -> error
        OR.B    D3,D2                           | D2 = full 8-bit checksum B
        CMP.B   D2,D6                           | compare with accumulated D6
        BNE.B   SONY_RDDATA_ERR_2               | mismatch -> checksum error
        ROL.B   #0x2,D1                         | rotate last 2 checksum bits
        AND.B   D0,D1                           | mask high 2 bits of checksum C
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_9              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_9:
        MOVE.B  (A4),D3                         | read checksum byte for D7
        BPL.B   SONY_RDDATA_SKIP_9              | poll until valid
        MOVE.B  0x0(A3,D3.W),D3                 | GCR decode: low 6 checksum bits
        BMI.B   SONY_RDDATA_ERR_2               | invalid GCR byte -> error
        OR.B    D3,D1                           | D1 = full 8-bit checksum C
        CMP.B   D1,D7                           | compare with accumulated D7
        BEQ.B   SONY_RDDATA_CONT_12             | test the checksum
| Branch from: SONY_RDDATA_SKIP_8, SONY_RDDATA_CONT_10, SONY_RDDATA_CONT_11, SONY_RDDATA_SKIP_9
SONY_RDDATA_ERR_2:
        MOVEQ.L #-0x48,D0                       | badDCkSum (-72): data checksum wrong or invalid nibble
        BRA.B   SONY_RDDATA_CONT_13             | return the error
SONY_RDDATA_ERR_3:
        MOVEQ.L #-0x44,D0                       | dataVerErr (-68): read-verify compare failed
        BRA.B   SONY_RDDATA_CONT_13             | return the error
SONY_RDDATA_CONT_12:
        MOVEQ.L #0x1,D4                         | D4 = 1: expect 2 trailer bytes ($DE $AA)
SONY_RDDATA_LOOP_5:
        MOVE.B  (A4),D3                         | read trailer byte from disk
        BPL.B   SONY_RDDATA_LOOP_5              | poll until valid
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_10             | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_10:
        CMP.B   (A2)+,D3                        | compare trailer against $DE, $AA
        BNE.B   SONY_RDDATA_ERR_4               | mismatch -> bad data bit-slip
        DBF     D4,SONY_RDDATA_LOOP_5           | read next trailer byte
        MOVEQ.L #0x0,D0                         | noErr: data read successful
SONY_RDDATA_CONT_13:
        BRA.W   TAIL_DRV_DSKRTN                 | return through DskRtn
SONY_RDDATA_ERR_4:
        MOVEQ.L #-0x49,D0                       | badDBtSlp (-73): data field slip marks wrong
        BRA.B   SONY_RDDATA_CONT_13             | return the error
| GCR decode table (denibblize, Apple: DNib): disk nibble $96..$FF ->
| 6-bit value, $FF for the other nibbles (among them the mark bytes $AA
| and $D5); RdAddr/RdData index it with the disk byte (base
| SONY_DENIBLTBL-$96). Only the checksum nibbles are checked for $FF.
SONY_DENIBLTBL:
        .byte   0x00,0x01,0xFF,0xFF,0x02,0x03   | disk $96-$97, $9A-$9B -> values 0-3
        .byte   0xFF,0x04,0x05,0x06,0xFF,0xFF   | disk $9D-$9F -> values 4-6
        .byte   0xFF,0xFF,0xFF,0xFF,0x07,0x08   | disk $A6-$A7 -> values 7-8
        .byte   0xFF,0xFF,0xFF,0x09,0x0A,0x0B   | disk $AB-$AD -> values 9-11 ($AA invalid)
        .byte   0x0C,0x0D,0xFF,0xFF,0x0E,0x0F   | disk $AE-$AF, $B2-$B3 -> values 12-15
        .byte   0x10,0x11,0x12,0x13,0xFF,0x14   | disk $B4-$B7, $B9 -> values 16-20
        .byte   0x15,0x16,0x17,0x18,0x19,0x1A   | disk $BA-$BF -> values 21-26
        .byte   0xFF,0xFF,0xFF,0xFF,0xFF,0xFF   | disk $C0-$C5: invalid ($FF)
        .byte   0xFF,0xFF,0xFF,0xFF,0xFF,0x1B   | disk $CB -> value 27
        .byte   0xFF,0x1C,0x1D,0x1E,0xFF,0xFF   | disk $CD-$CF -> values 28-30
        .byte   0xFF,0x1F,0xFF,0xFF,0x20,0x21   | disk $D3, $D6-$D7 -> values 31-33 ($D5 invalid)
        .byte   0xFF,0x22,0x23,0x24,0x25,0x26   | disk $D9-$DD -> values 34-38
        .byte   0x27,0x28,0xFF,0xFF,0xFF,0xFF   | disk $DE-$DF -> values 39-40
        .byte   0xFF,0x29,0x2A,0x2B,0xFF,0x2C   | disk $E5-$E7, $E9 -> values 41-44
        .byte   0x2D,0x2E,0x2F,0x30,0x31,0x32   | disk $EA-$EF -> values 45-50
        .byte   0xFF,0xFF,0x33,0x34,0x35,0x36   | disk $F2-$F5 -> values 51-54
        .byte   0x37,0x38,0xFF,0x39,0x3A,0x3B   | disk $F6-$F7, $F9-$FB -> values 55-59
        .byte   0x3C,0x3D,0x3E,0x3F             | disk $FC-$FF -> values 60-63
| AdrMkTbl (SyncTbl) -- the 27-byte skeleton of a sector header used
| by Format: sync group, address mark, sync group, data mark (in the
| 1987 SE driver it follows NiblTbl); FillInMarks fills in the nibbles
| at offsets 9-13 and 26. The first 6 bytes are also the sync group
| that DoFormat writes between the sectors.
SONY_ADRMKTBL:
        .byte   0xFF,0x3F,0xCF,0xF3,0xFC,0xFF   | 0-5: the six self-sync bytes (also SyncTbl)
        .byte   0xD5,0xAA,0x96,0x00,0x00,0x00   | 6-8: address mark $D5 $AA $96; 9-11: track, sector, side
        .byte   0x00,0x00,0xDE,0xAA,0xFF,0xFF   | 12-13: format byte, checksum; 14-16: $DE $AA $FF; 17: self-sync...
        .byte   0x3F,0xCF,0xF3,0xFC,0xFF,0xD5   | 18-22: ...self-sync bytes; 23: data mark $D5...
        .byte   0xAA,0xAD,0x00,0x00             | 24-25: ...$AA $AD; 26: sector; 27: not copied (headers are 27 bytes)

| -------------------------------------------------------------------------
| CtlFormat -- format the disk (csCode 6, floppy)
|   CSParam (in) -- format: 0 = as the disk is now (default), else the
|                   number of an entry of the format list (status 6):
|                   1 = 400K, 2 = 800K, 3 = 720K MFM (SuperDrive), for a
|                   1440K disk 1 = 1440K MFM; paramErr if out of range
| Selects GCR or MFM (mfmDisk) and the register set (SetChipMode), checks
| the write protection (wPrErr), builds the 12 GCR sector headers in a
| 512-byte stack buffer, then formats tracks 0-79 with SpdSeek and
| FormatTrack (GCR) or mFmtTrack (MFM, in the driver; both sides). Exits
| through FmtVerExit (shared with CtlVerify).
| -------------------------------------------------------------------------
Sony_CtlFormat:
        SUBA    #0x200,SP                       | 512-byte buffer on the stack
        MOVE.L  SP,DiskBuffer(A1)               | DiskBuffer = buffer (sector headers)
        MOVE.W  0x1C(A0),D4                     | CSParam: format number (0 = current format)
        BEQ.B   SONY_CTLFORMAT_SETCHIP          | 0 -> keep the format
        MOVEQ.L #0x2,D3                         | 2 formats without a SWIM or SuperDrive
        MOVE.B  isSWIM(A1),D0                   | isSWIM
        AND.B   mfmDrive(A1,D1.W),D0            | and mfmDrive: SWIM and SuperDrive?
        BPL.B   SONY_CTLFORMAT_CHKFMT           | no ->
        MOVEQ.L #0x3,D3                         | 3 formats (400K, 800K, 720K)
        TST.B   twoMegFmt(A1,D1.W)              | twoMegFmt: 1440K disk?
        BPL.B   SONY_CTLFORMAT_CHKFMT           | no ->
        MOVEQ.L #0x1,D3                         | 1440K disk: one format
SONY_CTLFORMAT_CHKFMT:
        MOVEQ.L #-0x32,D0                       | paramErr in case the number is out of range
        CMP.W   D3,D4                           | above the number of formats?
        BHI.W   SONY_FMTVEREXIT                 | yes -> paramErr
        CMPI.W  #0x3,D4                         | format 3 (720K)?
        SEQ.B   D0                              | D0 = $FF for 720K MFM
        OR.B    twoMegFmt(A1,D1.W),D0           | or a 1440K disk
        SMI.B   mfmDisk(A1,D1.W)                | mfmDisk = $FF for an MFM format
SONY_CTLFORMAT_SETCHIP:
        TST.B   isSWIM(A1)                      | isSWIM: SWIM installed?
        BPL.B   SONY_CTLFORMAT_SELECT           | no -> skip
        BSR.W   TAIL_DRV_SETCHIPMODE            | SetChipMode: register set for GCR or MFM
        BNE.W   SONY_FMTVEREXIT                 | error -> exit
SONY_CTLFORMAT_SELECT:
        BSR.W   TAIL_DRV_DISKSELECT             | DiskSelect: select the drive again
        TST.B   mfmDisk(A1,D1.W)                | mfmDisk: MFM format?
        SMI.B   TwoSided(A1)                    | TwoSided = $FF for MFM (always two-sided)
        BMI.B   SONY_CTLFORMAT_SIDES            | MFM ->
        TST.B   Sides(A1,D1.W)                  | Sides: double-sided drive?
        SMI.B   TwoSided(A1)                    | TwoSided = $FF: format both sides
        BPL.B   SONY_CTLFORMAT_SIDES            | one-sided drive -> one-sided format
        SUBQ.W  #0x1,D4                         | format number 1 (400K) on a two-sided drive?
        BNE.B   SONY_CTLFORMAT_SIDES            | no ->
        CLR.B   TwoSided(A1)                    | one-sided format
SONY_CTLFORMAT_SIDES:
        TST.B   TwoSided(A1)                    | one or two sides?
        SNE.B   TwoSideFmt(A1,D1.W)             | TwoSideFmt of the drive = the format we write
        MOVE    #0x7,GapSync(A1)                | GapSync = 7 sync groups between sectors to start with (System 7.1: 8)
        BSR.W   SONY_FVPOWERUP                  | FVPowerUp: power up (synchronously)
        MOVEQ.L #0x6,D0                         | WrProtAdr (6): write-protect sense
        BSR.W   TAIL_DRV_ADRANDSENSE            | AdrAndSense: sense = 0 when write-protected
        BMI.B   SONY_CTLFORMAT_BUILD            | not protected -> go on
        MOVEQ.L #-0x2C,D0                       | wPrErr (-44): disk is write-protected
        BRA.B   SONY_FMTVEREXIT                 | exit
SONY_CTLFORMAT_BUILD:
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        MOVE.L  DiskBuffer(A1),A0               | A0 = header buffer
        LEA.L   SONY_ADRMKTBL(PC),A1            | A1 -> AdrMkTbl
        MOVEQ.L #0xB,D0                         | 12 sector headers
SONY_CTLFORMAT_MARKS:
        MOVEQ.L #0x1A,D1                        | 27 bytes each
        MOVE.L  A1,A2                           | A2 -> skeleton
SONY_CTLFORMAT_MARKS_2:
        MOVE.B  (A2)+,(A0)+                     | copy a byte
        DBF     D1,SONY_CTLFORMAT_MARKS_2       | 27 times
        DBF     D0,SONY_CTLFORMAT_MARKS         | 12 times
        BSR.W   TAIL_DRV_GETDRV1                | GetDrv1
        CLR     SideTrack(A1)                   | SideTrack = 0: start with track 0, side 0
SONY_CTLFORMAT_TRACKLOOP:
        BSR.B   SONY_SPDSEEK                    | SpdSeek: seek, check the speed
        BNE.B   SONY_FMTVEREXIT                 | error -> exit
        BSR.W   TAIL_DRV_GETDRV1                | GetDrv1
        TST.B   mfmDisk(A1,D1.W)                | mfmDisk: MFM format?
        BPL.B   SONY_CTLFORMAT_GCR              | no -> GCR
        BSR.W   TAIL_DRV_MFMTTRACK              | mFmtTrack (driver): format both sides MFM
        BRA.B   SONY_CTLFORMAT_NEXT             | ->
SONY_CTLFORMAT_GCR:
        BSR.W   SONY_FORMATTRACK                | FormatTrack: format the track GCR
SONY_CTLFORMAT_NEXT:
        BNE.B   SONY_FMTVEREXIT                 | error -> exit
        BSR.W   TAIL_DRV_GETDRV1                | GetDrv1
        BCLR    #0x3,SideTrack(A1)              | side 0
        ADDQ.W  #0x1,SideTrack(A1)              | next track
        CMPI    #0x50,SideTrack(A1)             | all 80 tracks?
        BLT.B   SONY_CTLFORMAT_TRACKLOOP        | no -> next track
        MOVEQ.L #0x0,D0                         | noErr
| Branch from: SONY_CTLFORMAT_CHKFMT, SONY_CTLFORMAT_SETCHIP, SONY_CTLFORMAT_SIDES, SONY_CTLFORMAT_TRACKLOOP, SONY_CTLFORMAT_NEXT (and 2 more)
SONY_FMTVEREXIT:
        ADDA    #0x200,SP                       | release the stack buffer
        BRA.W   TAIL_DRV_DSKRWOFF               | DskRWOff (driver): power down and complete the request
| speed limits used by SpdSeek: the same midpoints as SpeedCheckTbl,
| +-1% instead of +-2%
SONY_FMTSPEEDTBL:
        .byte   0x11,0xBC,0x11,0x62,0x13,0x59   | zone 0: hi=0x11BC, lo=0x1162; zone 1 hi=0x1359
        .byte   0x12,0xF7,0x15,0x49,0x14,0xDD   | zone 1 lo=0x12F7; zone 2: hi=0x1549, lo=0x14DD
        .byte   0x17,0xA6,0x17,0x2E,0x1A,0x9A   | zone 3: hi=0x17A6, lo=0x172E; zone 4 hi=0x1A9A
        .byte   0x1A,0x14                       | zone 4 lo=0x1A14

| -------------------------------------------------------------------------
| SpdSeek -- seek to SideTrack (synchronously); for an old-interface
| drive, measure and adjust the speed at the first track of each zone
|   D0 (out) -- 0 or error code
| -------------------------------------------------------------------------
SONY_SPDSEEK:
        MOVE.B  BadSpdInit(A1),BadSpdCnt(A1)    | BadSpdCnt = BadSpdInit
SONY_SPDSEEK_CKDRIFT:
        MOVE    SideTrack(A1),D6                | CkDrift: D6 = side/track wanted
        BSR.W   SONY_FMTVERSEEK                 | FmtVerSeek: seek synchronously
        BSR.W   TAIL_DRV_GETDRV1                | GetDrv1
        MOVE    Track(A1,D1.W),D6               | D6 = current track
        BMI.B   SONY_SPDSEEK_EXIT               | negative after a seek error -> exit
        TST.B   NewIntf(A1,D1.W)                | new-interface drive?
        BMI.B   SONY_SPDSEEK_OK                 | yes -> no speed check
        MOVEQ.L #0xF,D0                         | mask: track mod 16
        AND.B   D6,D0                           | D0 = track mod 16
        BNE.B   SONY_SPDSEEK_OK                 | not the first track of a zone -> done
        LSR     #0x4,D6                         | zone
        LSL     #0x3,D6                         | * 8
        LEA.L   TrkSpeedTbl(A1,D1.W),A2         | A2 -> TrkSpeedTbl
        LEA.L   0x4(A2,D6.W),A2                 | A2 -> time of the last check of this zone
        MOVE.L  (Ticks).w,D2                    | Ticks
        MOVE.L  D2,(A2)                         | note the time of this check
        LEA.L   SONY_SPDSEEK_CHECK(PC),A3       | return address for the measurement
        BRA.W   TAIL_DRV_GETFREQ1               | GetFreq1 (driver): measure the speed
| SONY_SPDSEEK_CHECK -- speed check callback for format (tighter tolerances)
SONY_SPDSEEK_CHECK:
        BMI.B   SONY_SPDSEEK_ERR                | measurement failed -> spdAdjErr
        MOVE    -(A2),D0                        | D0 = TSTblDelta: speed code change for 2% speed
        LSR     #0x1,D0                         | half of it
        LEA.L   SONY_FMTSPEEDTBL(PC),A0         | A0 -> format speed limits
        LSR     #0x1,D6                         | zone * 4
        ADDA    D6,A0                           | A0 -> limits of this zone
        CMP     (A0)+,D4                        | too fast (speed value above the upper limit)?
        BGT.B   SONY_SPDSEEK_ADJUST             | yes -> adjust
        NEG     D0                              | else D0 = -delta/2
        CMP     (A0),D4                         | too slow (at or below the lower limit)?
        BGT.B   SONY_SPDSEEK_OK                 | no -> speed is fine
SONY_SPDSEEK_ADJUST:
        SUB     D0,-(A2)                        | TSTblCode -= delta/2 (fast) or += delta/2 (slow)
        CLR.L   0x4(A2)                         | force a recheck
        SUBQ.B  #0x1,BadSpdCnt(A1)              | BadSpdCnt: adjustments left?
        BPL.B   SONY_SPDSEEK_CKDRIFT            | yes -> seek and check again
SONY_SPDSEEK_ERR:
        MOVEQ.L #-0x4F,D0                       | spdAdjErr (-79)
        BRA.B   SONY_SPDSEEK_EXIT               | return
| SpdSeekOK -- speed OK (or a new-interface drive)
SONY_SPDSEEK_OK:
        MOVEQ.L #0x0,D0                         | noErr
SONY_SPDSEEK_EXIT:
        RTS                                     | return

| -------------------------------------------------------------------------
| FormatTrack -- format the current track (both sides for a two-sided
| format), adjusting GapSync until the inter-sector gap is even
|   D0 (out) -- 0 or error code (also in DskErr)
| -------------------------------------------------------------------------
SONY_FORMATTRACK:
        BSR.W   TAIL_DRV_GETDRV1                | GetDrv1
        MOVE    SideTrack(A1),D6                | D6 = side/track
        MOVE    D6,D1                           | D1 = track
        BCLR    #0xB,D1                         | without the side bit
        LSR     #0x4,D1                         | zone
        MOVEQ.L #0xC,D0                         | 12 sectors in zone 0,
        SUB     D1,D0                           | one less per zone inward
        MOVE    D0,SectCnt(A1)                  | SectCnt = sectors on this track
        BSR.W   SONY_FILLINMARKS                | FillInMarks: track/sector fields of the headers
| SONY_FORMATTRACK_1 -- write raw track then verify
SONY_FORMATTRACK_1:
        BSR.B   SONY_DOFORMAT                   | FmtTrk1: DoFormat: write the track
        BEQ.B   SONY_FORMATTRACK_CHECK          | ok -> check the gap
        BSR.W   SONY_TOEMPTYPD                  | toEmptyPD: save the error, poll data
        ANDI    #-0x701,SR                      | open interrupts
        BRA.W   SONY_FORMATTRACK_EXIT           | exit with the write error
| check the inter-sector gap (poll data stays on the stack)
SONY_FORMATTRACK_CHECK:
        BSR.W   E_Sony_RdAddr                   | RdAddr: the next address mark
        BMI.B   SONY_FORMATTRACK_GAP            | error ->
        TST.B   D2                              | should be sector 0
        BEQ.B   SONY_FORMATTRACK_GAP            | it is ->
        MOVEQ.L #-0x52,D0                       | fmt1Err (-82): not sector 0
SONY_FORMATTRACK_GAP:
        BSR.W   SONY_TOEMPTYPD                  | toEmptyPD (preserves D0)
        ANDI    #-0x701,SR                      | open interrupts
        LEA.L   GapSync(A1),A0                  | A0 -> GapSync
        MOVE    (DskErr).w,D0                   | RdAddr result (via toEmptyPD): count left, or an error
        BMI.B   SONY_FORMATTRACK_DECRSN1        | error -> fewer sync groups
        MOVE.L  #0x5E0,D2                       | MustFindCt + 4 = 1504
        SUB     D0,D2                           | - count left = nibbles read before sector 0 (the gap)
        DIVU    #0x5,D2                         | / 5 = sync groups in that gap (a sync group reads as five $FF nibbles)
        MOVE    #-0x53,(DskErr).w               | assume fmt2Err (-83): not enough sync
        SUB     (A0),D2                         | - GapSync = groups more than standard
        BMI.B   SONY_FORMATTRACK_DECRSYNC       | too few -> DecrSync
        EXT.L   D2                              | extend for DIVU
        DIVU    SectCnt(A1),D2                  | / sectors = extra groups per sector
        BEQ.B   SONY_FORMATTRACK_OK             | none ->
        SUBQ.W  #0x1,D2                         | just one -> leave GapSync alone
        BEQ.B   SONY_FORMATTRACK_OK             | ->
        ADDQ.W  #0x1,(A0)                       | else GapSync + 1
SONY_FORMATTRACK_OK:
        BSR.W   TAIL_DRV_GETDRV1                | FTExitOK: GetDrv1
        BSET    #0x3,SideTrack(A1)              | side 1 done already?
        BNE.B   SONY_FORMATTRACK_DONE           | yes ->
        TST.B   TwoSided(A1)                    | two-sided format?
        BNE.B   SONY_FORMATTRACK                | yes -> format side 1
SONY_FORMATTRACK_DONE:
        CLR     (DskErr).w                      | success: DskErr = 0
SONY_FORMATTRACK_EXIT:
        MOVE    (DskErr).w,D0                   | FTExit: D0 = DskErr
        RTS                                     | return
| DecrSync / DecrSn1 -- fewer sync groups (not below minSync = 4)
SONY_FORMATTRACK_DECRSYNC:
        ADDQ.W  #0x1,D2                         | only one too few?
        BEQ.B   SONY_FORMATTRACK_OK             | yes -> accept
SONY_FORMATTRACK_DECRSN1:
        SUBQ.W  #0x1,(A0)                       | GapSync - 1
        CMPI    #0x4,(A0)                       | below minSync (4)?
        BLT.B   SONY_FORMATTRACK_EXIT           | yes -> give up (fmt2Err)
        BRA.B   SONY_FORMATTRACK_1              | FmtTrk1: format the track again

| -------------------------------------------------------------------------
| DoFormat -- write the current track (interrupts disabled): 200 sync
| groups, then for each sector GapSync sync groups, the 27-byte header,
| 703 data nibbles ($96) and the bit-slip marks; 2:1 interleave from the
| headers built by FillInMarks. 703 = 699 data + 4 checksum nibbles (the
| SWIM Chip User's Reference figure counts "699+3"), all $96 (6-bit
| value 0): the sector reads as 524 zero bytes with correct checksums.
| -------------------------------------------------------------------------
SONY_DOFORMAT:
        MOVE.L  (SP)+,(DskRtnAdr).w             | strip the return address
        MOVEQ.L #0x1,D0                         | RdDtaAdr: side 0
        MOVE.L  (SonyVars).w,A1                 | reload SonyVars
        TST.B   TwoSided(A1)                    | two-sided format?
        BEQ.B   SONY_DOFORMAT_SIDE              | no -> side 0
        BTST    #0xB,D6                         | side 1 (bit 11)?
        BEQ.B   SONY_DOFORMAT_SIDE              | no -> side 0
        MOVEQ.L #0x3,D0                         | RdDta1Adr: side 1
SONY_DOFORMAT_SIDE:
        BSR.W   TAIL_DRV_ADRDISK                | AdrDisk: select the head
        MOVEQ.L #0x4,D0                         | PollStack = SP + 4 (one return address)
        BSR.W   E_Sony_SetUpPoll                | SetUpPoll: A5, A6, PollStack
        MOVEA.L (IWM).w,A4                      | A4 = IWM base (low-memory IWM)
        LEA.L   0x1A00(A4),A3                   | A3 -> q6H: write data register
        MOVE.L  DiskBuffer(A1),A0               | A0 -> sector headers
        MOVE    SectCnt(A1),D0                  | D0 = sector count
        MOVE    GapSync(A1),D1                  | D1 = GapSync
        SUBQ.W  #0x2,D1                         | - 2 for DBRA and the header sync group
        LEA.L   SONY_ADRMKTBL(PC),A1            | A1 -> SyncTbl (sync group)
        MOVE    #0xC7,D3                        | 200 sync groups (strtSync)
        TST.B   (A3)                            | q6H: L6 = 1
        MOVE.B  D3,0x1E00(A4)                   | first byte at q7H (the count $C7, Apple: "write garbage to start"): write state
        LEA.L   0x1800(A4),A4                   | A4 -> q6L: write-handshake register in the write state
| SONY_DOFORMAT_STRTSYNC -- write initial self-sync ($FF) bytes, D3+1 groups of 6 bytes
SONY_DOFORMAT_STRTSYNC:
        MOVE.L  A1,A2                           | WrStrtSync: A2 -> sync group
        MOVEQ.L #0x2,D2                         | 3 pairs of nibbles
SONY_DOFORMAT_WSS1:
        MOVE.B  (A2)+,D4                        | prefetch
SONY_DOFORMAT_WSS1_HSHK:
        TST.B   (A4)                            | write handshake ready?
        BPL.B   SONY_DOFORMAT_WSS1_HSHK         | no -> wait
        MOVE.B  D4,(A3)                         | write a sync nibble
        MOVE.B  (A2)+,D4                        | prefetch
        TST.B   (A5)                            | SCC data waiting?
        BMI.B   SONY_DOFORMAT_WSS1_HSHK2        | no ->
        MOVE.B  (A6),-(SP)                      | poll the SCC: byte onto the stack
SONY_DOFORMAT_WSS1_HSHK2:
        TST.B   (A4)                            | write handshake ready?
        BPL.B   SONY_DOFORMAT_WSS1_HSHK2        | no -> wait
        MOVE.B  D4,(A3)                         | write a sync nibble
        DBF     D2,SONY_DOFORMAT_WSS1           | 3 pairs
        DBF     D3,SONY_DOFORMAT_STRTSYNC       | 200 groups
| SONY_DOFORMAT_NXTSECT -- per-sector loop: write inter-sector sync, address, gap, data
SONY_DOFORMAT_NXTSECT:
        MOVE    D1,D3                           | WrNxtSect: D3 = GapSync - 2
SONY_DOFORMAT_GAP:
        MOVE.L  A1,A2                           | A2 -> sync group
        MOVEQ.L #0x5,D2                         | 6 nibbles
SONY_DOFORMAT_GAP_2:
        TST.B   (A4)                            | write handshake ready?
        BPL.B   SONY_DOFORMAT_GAP_2             | wait
        MOVE.B  (A2)+,(A3)                      | write a byte of the sync group
        TST.B   (A5)                            | SCC data waiting?
        BMI.B   SONY_DOFORMAT_GAP_3             | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | poll the SCC
SONY_DOFORMAT_GAP_3:
        DBF     D2,SONY_DOFORMAT_GAP_2          | 6 nibbles
        DBF     D3,SONY_DOFORMAT_GAP            | GapSync - 1 groups
| the sector header: sync group, address mark, sync group, data mark
        MOVEQ.L #0x1A,D2                        | 27 nibbles
SONY_DOFORMAT_ADRMK:
        TST.B   (A4)                            | write handshake ready?
        BPL.B   SONY_DOFORMAT_ADRMK             | wait
        MOVE.B  (A0)+,(A3)                      | write a header nibble
        TST.B   (A5)                            | SCC data waiting?
        BMI.B   SONY_DOFORMAT_ADRMK_2           | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | poll the SCC
SONY_DOFORMAT_ADRMK_2:
        DBF     D2,SONY_DOFORMAT_ADRMK          | 27 nibbles
| the data field: 703 nibbles of $96 (encoded zeros)
        MOVE    #0x2BE,D2                       | 703 nibbles
SONY_DOFORMAT_DATA:
        TST.B   (A4)                            | write handshake ready?
        BPL.B   SONY_DOFORMAT_DATA              | wait
        MOVE.B  #0x96,(A3)                      | write $96
        TST.B   (A5)                            | SCC data waiting?
        BMI.B   SONY_DOFORMAT_DATA_2            | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | poll the SCC
SONY_DOFORMAT_DATA_2:
        DBF     D2,SONY_DOFORMAT_DATA           | 703 nibbles
| then the slip marks $DE $AA and two $FF (AdrMkTbl+14)
        MOVEQ.L #0x3,D2                         | 4 nibbles
        ADDQ.W  #0x8,A2                         | A2 -> bit-slip marks (DE AA FF FF)
SONY_DOFORMAT_SLIP:
        TST.B   (A4)                            | write handshake ready?
        BPL.B   SONY_DOFORMAT_SLIP              | wait
        MOVE.B  (A2)+,(A3)                      | write a bit-slip nibble
        DBF     D2,SONY_DOFORMAT_SLIP           | 4 nibbles
        SUBQ.W  #0x1,D0                         | count the sector
        BGT.B   SONY_DOFORMAT_NXTSECT           | next sector
| check the write status
        MOVE.B  (A4),D0                         | write-handshake register: bit 6 = 0 after an underrun
        MOVEQ.L #0x0,D2                         | assume no underrun
        BTST    #0x6,D0                         | bit 6 = 0: write underrun?
        BNE.B   SONY_DOFORMAT_OK                | no ->
        MOVEQ.L #-0x4A,D0                       | wrUnderrun (-74)
        BRA.B   SONY_DOFORMAT_EXIT              | exit write mode
| SONY_DOFORMAT_OK -- write completed successfully
SONY_DOFORMAT_OK:
        MOVEQ.L #0x0,D0                         | noErr
SONY_DOFORMAT_EXIT:
        TST.B   0x200(A3)                       | q7L (A3+$200): L7 = 0, write state off (Apple: "after half of garbage nibble is written")
        MOVE.L  (DskRtnAdr).w,-(SP)             | continue at DskRtnAdr
        TST     D0                              | CCR = result
        RTS                                     | return there

| -------------------------------------------------------------------------
| FillInMarks -- fill in the track, sector, side, format byte and checksum
| of the 12 sector headers (D6 = side/track, D0 = sector count); sectors
| are numbered 0, n/2, 1, n/2+1, ... (2:1 interleave). Registers kept.
| -------------------------------------------------------------------------
SONY_FILLINMARKS:
        MOVEM.L D0-D7/A0-A1,-(SP)               | save registers
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        MOVE.L  DiskBuffer(A1),A0               | A0 -> header buffer
        MOVEQ.L #0x2,D3                         | FmtByte $02: 2:1 interleave, one-sided
        TST.B   TwoSided(A1)                    | two-sided?
        BEQ.B   SONY_FILLINMARKS_1              | no ->
        MOVEQ.L #0x22,D3                        | Fmt2Byte $22: 2:1 interleave, $20 = two-sided ("FMT BYTE has INTLV", hand notes)
SONY_FILLINMARKS_1:
        MOVE.L  (DiskVars_NiblTbl).w,A1         | A1 -> NiblTbl
        MOVE.B  0x0(A1,D3.W),D7                 | D7 = encoded format byte
        MOVE.B  D3,D5                           | start the checksum
        MOVEQ.L #0x3F,D3                        | 6-bit mask
        AND.B   D6,D3                           | track bits 0-5
        MOVE.B  0x0(A1,D3.W),D2                 | D2 = encoded track
        EOR.B   D3,D5                           | into the checksum
        LSR     #0x6,D6                         | side (now bit 5) and track bits 6-10
        EOR.B   D6,D5                           | into the checksum
        MOVE.B  0x0(A1,D6.W),D6                 | D6 = encoded side/track
        MOVE    D0,D1                           | sector count
        SUBQ.W  #0x1,D1                         | - 1
        LSR     #0x1,D1                         | / 2
        ADDQ.W  #0x1,D1                         | + 1 = second sector number
        SWAP    D1                              | (high word)
        CLR     D1                              | first sector number is always 0
SONY_FILLINMARKS_LOOP:
        MOVE.B  0x0(A1,D1.W),D3                 | D3 = encoded sector number
        MOVEQ.L #0x0,D4                         | D4 = 0 (word index)
        MOVE.B  D5,D4                           | checksum without the sector
        EOR.B   D1,D4                           | plus the sector
        ADDA    #0x9,A0                         | skip to the track field
        MOVE.B  D2,(A0)+                        | encoded track
        MOVE.B  D3,(A0)+                        | encoded sector
        MOVE.B  D6,(A0)+                        | encoded side
        MOVE.B  D7,(A0)+                        | encoded format byte
        MOVE.B  0x0(A1,D4.W),(A0)+              | encoded checksum
        ADDA    #0xC,A0                         | skip to the sector byte of the data mark
        MOVE.B  D3,(A0)+                        | encoded sector
        ADDQ.W  #0x1,D1                         | next sector of this half
        SWAP    D1                              | toggle between the two halves
        SUBQ.W  #0x1,D0                         | count it
        BNE.B   SONY_FILLINMARKS_LOOP           | more ->
        MOVEM.L (SP)+,D0-D7/A0-A1               | restore registers
        RTS                                     | return

| -------------------------------------------------------------------------
| CtlVerify -- verify the disk (csCode 5, floppy): read every sector of
| every track, from track 79 down to 0 (zone by zone: the GCR sector map
| grows by one sector per zone); GCR tracks with VerTrack, MFM tracks
| with mVerTrack in the driver (both sides). Sets up the register set
| first (SetChipMode).
| -------------------------------------------------------------------------
Sony_CtlVerify:
        SUBA    #0x200,SP                       | 512-byte buffer on the stack
        MOVE.L  SP,DiskBuffer(A1)               | DiskBuffer = buffer
        TST.B   isSWIM(A1)                      | isSWIM: SWIM installed?
        BPL.B   SONY_CTLVERIFY_START            | no -> skip
        BSR.W   TAIL_DRV_SETCHIPMODE            | SetChipMode: register set for the disk
        BNE.W   SONY_FMTVEREXIT                 | error -> exit
SONY_CTLVERIFY_START:
        BSR.W   SONY_FVPOWERUP                  | FVPowerUp
        MOVEQ.L #0x4,D2                         | 5 zones
        MOVE    #0x7F,D4                        | sector map for track 79 (almost)
        MOVEQ.L #0x4F,D6                        | track 79
SONY_CTLVERIFY_CLASS:
        LSL     #0x1,D4                         | NxtVClass: one more sector
        ADDQ.W  #0x1,D4                         | in this zone
        MOVEQ.L #0xF,D3                         | 16 tracks per zone
SONY_CTLVERIFY_TRACK:
        MOVEM.L D2-D6,-(SP)                     | NxtVTrk
        BSR.W   SONY_FMTVERSEEK                 | FmtVerSeek: seek to D6 (synchronously)
        MOVEM.L (SP)+,D2-D6                     | restore zone/track state
        BSR.W   TAIL_DRV_GETDRV1                | GetDrv1
        MOVE    Track(A1,D1.W),D0               | current track
        BMI.B   SONY_CTLVERIFY_EXIT             | negative after a seek error -> exit
        TST.B   mfmDisk(A1,D1.W)                | mfmDisk: MFM disk?
        BPL.B   SONY_CTLVERIFY_GCR              | no -> GCR
        BSR.W   TAIL_DRV_MVERTRACK              | mVerTrack (driver): verify both sides MFM
        BRA.B   SONY_CTLVERIFY_NEXT             | ->
SONY_CTLVERIFY_GCR:
        BSR.B   SONY_VERTRACK                   | VerTrack
SONY_CTLVERIFY_NEXT:
        BNE.B   SONY_CTLVERIFY_EXIT             | error -> exit
        SUBQ.W  #0x1,D6                         | next track
        DBF     D3,SONY_CTLVERIFY_TRACK         | rest of the zone
        DBF     D2,SONY_CTLVERIFY_CLASS         | next zone
SONY_CTLVERIFY_EXIT:
        BRA.W   SONY_FMTVEREXIT                 | FmtVerExit
| VerTrack -- read every sector of the current track (both sides of a
| two-sided disk); SectMapSave holds [map side 0][tries][map side 1][tries]
SONY_VERTRACK:
        MOVEM.L D2-D6,-(SP)                     | save registers
        ORI     #0x300,SR                       | no interrupts
        LEA.L   SectMapSave(A1),A0              | A0 -> SectMapSave
        MOVE    D4,(A0)                         | map of this track
        MOVEQ.L #0xC,D3                         | 12
        SUB     D2,D3                           | - zone = sectors on this track
        LSL     #0x2,D3                         | * 4: allow some slop (may not get 1-1)
        MOVE    D3,0x2(A0)                      | tries
        MOVE.L  (A0)+,(A0)+                     | duplicate for side 1
        BCLR    #0x3,SideTrack(A1)              | side 0
SONY_VERTRACK_LOOP:
        MOVE.L  D1,D6                           | VTLoop: D6 = drive vars offset
        BSR.W   Sony_RdAddrSetup                | RdAddrSetup: next address mark
        BPL.B   SONY_VERTRACK_1                 | ok ->
        BSR.B   SONY_TOEMPTYPD                  | toEmptyPD
        ANDI    #-0x701,SR                      | open interrupts
        BRA.B   SONY_VERTRACK_EXIT              | exit with the error
SONY_VERTRACK_1:
        LEA.L   SectSave(A1),A0                 | A0 -> SectSave
        MOVE    D2,(A0)+                        | sector number
        MOVE    (A0)+,D0                        | sector map
        BCLR    D2,D0                           | sector still wanted?
        BNE.B   SONY_VERTRACK_2                 | yes -> read it
        BSR.B   SONY_TOEMPTYPD                  | toEmptyPD
        ANDI    #-0x701,SR                      | open interrupts
        LEA.L   SectMapSave+2(A1),A0            | A0 -> tries (SectMapSave+2)
        BRA.B   SONY_VERTRACK_3                 | count the try
SONY_VERTRACK_2:
        CMPI.B  #0x1F,D3                        | format byte > $1F
        SGT.B   TwoSideFmt(A1,D6.W)             | TwoSideFmt = $FF for a two-sided disk
        MOVE.L  DiskBuffer(A1),A0               | A0 = buffer
        CLR.B   (DskVerify).w                   | never read-verify here
        BSR.W   E_Sony_RdData                   | RdData
        BSR.B   SONY_TOEMPTYPD                  | toEmptyPD
        TST     D0                              | read ok?
        BNE.B   SONY_VERTRACK_EXIT              | no -> exit
        LEA.L   SectSave(A1),A0                 | A0 -> SectSave
        MOVE    (A0)+,D2                        | sector just read
        MOVE    (A0),D0                         | sector map
        BCLR    D2,D0                           | mark it read
        MOVE    D0,(A0)+                        | store the map
        BEQ.B   SONY_VERTRACK_OK                | all read -> next side or done
SONY_VERTRACK_3:
        SUBQ.W  #0x1,(A0)                       | count the try
        BNE.B   SONY_VERTRACK_LOOP              | tries left -> next address mark
        MOVEQ.L #-0x54,D0                       | verErr (-84): track did not verify
        BRA.B   SONY_VERTRACK_EXIT              | exit
SONY_VERTRACK_OK:
        BSR.W   TAIL_DRV_GETDRV1                | VTExitOK: GetDrv1
        TST.B   TwoSideFmt(A1,D1.W)             | two-sided format?
        BEQ.B   SONY_VERTRACK_DONE              | no -> done
        BSET    #0x3,SideTrack(A1)              | side 1 done already?
        BNE.B   SONY_VERTRACK_DONE              | yes -> done
        ADDQ.W  #0x2,A0                         | A0 -> copy of map/tries
        MOVE.L  (A0),-(A0)                      | copy it back
        BRA.B   SONY_VERTRACK_LOOP              | verify side 1
SONY_VERTRACK_DONE:
        MOVEQ.L #0x0,D0                         | noErr
SONY_VERTRACK_EXIT:
        ANDI    #-0x701,SR                      | VTExit: open interrupts
        MOVEM.L (SP)+,D2-D6                     | restore registers
        TST     D0                              | CCR = result
        RTS                                     | return
| toEmptyPD -- save D0 in DskErr and process the poll data
| Called by: TAILENT_TOEMPTYPD, SONY_FORMATTRACK_1, SONY_FORMATTRACK_GAP, SONY_VERTRACK_LOOP, SONY_VERTRACK_1 (and 1 more)
SONY_TOEMPTYPD:
        MOVE    D0,(DskErr).w                   | DskErr = result
        BRA.W   TAIL_DRV_EMPTYPD                | EmptyPD
| FmtVerSeek / FVPowerUp -- call Seek or RWPowerUp and wait until it
| completes (SyncCall; DskErr is the completion flag -- Apple's change
| <2> of 2 Feb 1990 uses Active instead, as DskErr also holds errors)
SONY_FMTVERSEEK:
        LEA.L   TAIL_DRV_SEEK(PC),A0            | FmtVerSeek: Seek
SONY_SYNCCALL:
        CLR.B   (DskErr).w                      | SyncCall: DskErr = 0: not done
        BSR.B   SONY_SYNCCALL_CALL              | call it
SONY_SYNCCALL_WAIT:
        TST.B   (DskErr).w                      | done?
        BEQ.B   SONY_SYNCCALL_WAIT              | no -> wait
        RTS                                     | return
| call (A0): a routine that waits (WakeUp) returns into the wait loop
| above at once; DskErr becomes $FF when it has really finished
SONY_SYNCCALL_CALL:
        JSR     (A0)                            | call the routine (returns early while waiting)
        ST.B    (DskErr).w                      | DskErr = $FF: done
        RTS                                     | return
| FVPowerUp -- RWPowerUp, synchronously
SONY_FVPOWERUP:
        LEA.L   TAIL_DRV_RWPOWERUP(PC),A0       | FVPowerUp: RWPowerUp
        BRA.B   SONY_SYNCCALL                   | synchronously

| -------------------------------------------------------------------------
| DrvTbl -- icon and drive information for physical drives 1-5 (the 1987
| SE driver's table): offset of the media icon, offset of the drive icon
| and the drive info word returned by csCode 23 (Inside Macintosh V-470;
| Technical Note #272: bits 0-3 drive type, 3 = 800K, 7 = HD20 here,
| csCode 23 reports 2 for 400K drives and 4 for SuperDrives; bit 8
| external, 9 SCSI, 10 fixed media, 11 secondary drive). DiskOpen stores
| its address in drvTblPtr (SonyVars+$178, SetDrvTbl); the icon calls
| take the table from there, so it can be replaced. An icon offset with
| bit 0 set is relative to this ROM table, one with bit 0 clear relative
| to the table drvTblPtr points to.
| -------------------------------------------------------------------------
DRVTBL:
        .short  ICON_DISKETTE-DRVTBL            | drive 1: media icon (csCode 22)
        .short  ICON_LOWERDRIVE-DRVTBL          | drive 1: drive icon (csCode 21)
        .short  0x0003                          | drive 1 info: 800K drive, primary internal removable
        .short  ICON_DISKETTE-DRVTBL            | drive 2: media icon (csCode 22)
        .short  ICON_UPPERDRIVE-DRVTBL          | drive 2: drive icon (csCode 21)
        .short  0x0803                          | drive 2 info: 800K drive, secondary internal removable
        .short  ICON_DISKETTE-DRVTBL            | drive 3: media icon (csCode 22)
        .short  ICON_EXTDRIVE-DRVTBL            | drive 3: drive icon (csCode 21)
        .short  0x0103                          | drive 3 info: 800K drive, primary external removable
        .short  ICON_DISKETTE-DRVTBL            | drive 4: media icon (csCode 22)
        .short  ICON_DISKETTE-DRVTBL            | drive 4: drive icon (csCode 21)
        .short  0x0507                          | drive 4 info: Hard Disk 20, primary external fixed
        .short  ICON_DISKETTE-DRVTBL            | drive 5: media icon (csCode 22)
        .short  ICON_DISKETTE-DRVTBL            | drive 5: drive icon (csCode 21)
        .short  0x0D07                          | drive 5 info: Hard Disk 20, secondary external fixed

| -------------------------------------------------------------------------
| Icons -- 32x32 icon and mask, followed by an empty Pascal string (the
| "Where:" string of the Finder's Get Info window) and a pad byte, the
| same four icons as in the 1987 SE driver: the 3.5-inch diskette (media
| icon of every drive), the external drive, and the Macintosh SE with an
| arrow to its lower or upper internal drive.
| -------------------------------------------------------------------------
| 3.5-inch diskette (media icon of all drives): icon
ICON_DISKETTE:
        .long   0x7FFFFFF8                      | .############################...
        .long   0x81000104                      | #......#...............#.....#..
        .long   0x81007102                      | #......#.........###...#......#.
        .long   0x81008901                      | #......#........#...#..#.......#
        .long   0x81008901                      | #......#........#...#..#.......#
        .long   0x81008901                      | #......#........#...#..#.......#
        .long   0x81008901                      | #......#........#...#..#.......#
        .long   0x81008901                      | #......#........#...#..#.......#
        .long   0x81007101                      | #......#.........###...#.......#
        .long   0x81000101                      | #......#...............#.......#
        .long   0x80FFFE01                      | #.......###############........#
        .long   0x80000001                      | #..............................#
        .long   0x80000001                      | #..............................#
        .long   0x80000001                      | #..............................#
        .long   0x80000001                      | #..............................#
        .long   0x80000001                      | #..............................#
        .long   0x80000001                      | #..............................#
        .long   0x80000001                      | #..............................#
        .long   0x87FFFFE1                      | #....######################....#
        .long   0x88000011                      | #...#......................#...#
        .long   0x88000011                      | #...#......................#...#
        .long   0x88000011                      | #...#......................#...#
        .long   0x88000011                      | #...#......................#...#
        .long   0x88000011                      | #...#......................#...#
        .long   0x88000011                      | #...#......................#...#
        .long   0x88000011                      | #...#......................#...#
        .long   0x88000011                      | #...#......................#...#
        .long   0x88000011                      | #...#......................#...#
        .long   0x88000011                      | #...#......................#...#
        .long   0x88000011                      | #...#......................#...#
        .long   0x88000011                      | #...#......................#...#
        .long   0x7FFFFFFE                      | .##############################.
| 3.5-inch diskette (media icon of all drives): mask
        .long   0x7FFFFFF8                      | .############################...
        .long   0xFFFFFFFC                      | ##############################..
        .long   0xFFFFFFFE                      | ###############################.
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0x7FFFFFFE                      | .##############################.
        .byte   0,0                             | empty Pascal string ("Where:"), pad byte
| external drive (drive 3): icon
ICON_EXTDRIVE:
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .long   0x7FFF8000                      | .################...............
        .long   0x80004000                      | #................#..............
        .long   0x9FFE4000                      | #..############..#..............
        .long   0xA0014000                      | #.#............#.#..............
        .long   0xA0014000                      | #.#............#.#..............
        .long   0xA0014000                      | #.#............#.#..............
        .long   0xA0014000                      | #.#............#.#..............
        .long   0xA0014000                      | #.#............#.#..............
        .long   0xA0014040                      | #.#............#.#.......#......
        .long   0xA0014040                      | #.#............#.#.......#......
        .long   0xA0014040                      | #.#............#.#.......#......
        .long   0x9FFE4040                      | #..############..#.......#......
        .long   0x800041F0                      | #................#.....#####....
        .long   0x800040E0                      | #................#......###.....
        .long   0x80004040                      | #................#.......#......
        .long   0x80FE4000                      | #.......#######..#..............
        .long   0x80005FFF                      | #................#.#############
        .long   0x80005001                      | #................#.#...........#
        .long   0x80005001                      | #................#.#...........#
        .long   0x800053F9                      | #................#.#..#######..#
        .long   0x7FFF9001                      | .################..#...........#
        .long   0x40009001                      | .#..............#..#...........#
        .long   0x7FFF9FFF                      | .################..#############
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
| external drive (drive 3): mask
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .long   0x7FFF8000                      | .################...............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFDFFF                      | ##################.#############
        .long   0xFFFFDFFF                      | ##################.#############
        .long   0xFFFFDFFF                      | ##################.#############
        .long   0xFFFFDFFF                      | ##################.#############
        .long   0x7FFF9FFF                      | .################..#############
        .long   0x7FFF9FFF                      | .################..#############
        .long   0x7FFF9FFF                      | .################..#############
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .byte   0,0                             | empty Pascal string ("Where:"), pad byte
| lower internal drive of the Macintosh SE (drive 1): icon
ICON_LOWERDRIVE:
        .long   0x00000000                      | ................................
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x08000010                      | ....#......................#....
        .long   0x08000010                      | ....#......................#....
        .long   0x08FFFF10                      | ....#...################...#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x09555090                      | ....#..#.#.#.#.#.#.#....#..#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x09550090                      | ....#..#.#.#.#.#........#..#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x09500090                      | ....#..#.#.#............#..#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x09500090                      | ....#..#.#.#............#..#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x09540090                      | ....#..#.#.#.#..........#..#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x08FFFF10                      | ....#...################...#....
        .long   0x08000010                      | ....#......................#....
        .long   0x08000010                      | ....#......................#....
        .long   0x0800FF10                      | ....#...........########...#....
        .long   0x08100010                      | ....#......#...............#....
        .long   0x08180010                      | ....#......##..............#....
        .long   0x08FCFF10                      | ....#...######..########...#....
        .long   0x08180010                      | ....#......##..............#....
        .long   0x08100010                      | ....#......#...............#....
        .long   0x08000010                      | ....#......................#....
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x04000020                      | .....#....................#.....
        .long   0x04000020                      | .....#....................#.....
        .long   0x04000020                      | .....#....................#.....
        .long   0x03FFFFC0                      | ......####################......
| lower internal drive of the Macintosh SE (drive 1): mask
        .long   0x00000000                      | ................................
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x03FFFFC0                      | ......####################......
        .byte   0,0                             | empty Pascal string ("Where:"), pad byte
| upper internal drive of the Macintosh SE (drive 2): icon
ICON_UPPERDRIVE:
        .long   0x00000000                      | ................................
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x08000010                      | ....#......................#....
        .long   0x08000010                      | ....#......................#....
        .long   0x08FFFF10                      | ....#...################...#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x09555090                      | ....#..#.#.#.#.#.#.#....#..#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x09550090                      | ....#..#.#.#.#.#........#..#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x09500090                      | ....#..#.#.#............#..#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x09500090                      | ....#..#.#.#............#..#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x09540090                      | ....#..#.#.#.#..........#..#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x08FFFF10                      | ....#...################...#....
        .long   0x08000010                      | ....#......................#....
        .long   0x08100010                      | ....#......#...............#....
        .long   0x08180010                      | ....#......##..............#....
        .long   0x08FCFF10                      | ....#...######..########...#....
        .long   0x08180010                      | ....#......##..............#....
        .long   0x08100010                      | ....#......#...............#....
        .long   0x0800FF10                      | ....#...........########...#....
        .long   0x08000010                      | ....#......................#....
        .long   0x08000010                      | ....#......................#....
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x04000020                      | .....#....................#.....
        .long   0x04000020                      | .....#....................#.....
        .long   0x04000020                      | .....#....................#.....
        .long   0x03FFFFC0                      | ......####################......
| upper internal drive of the Macintosh SE (drive 2): mask
        .long   0x00000000                      | ................................
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x03FFFFC0                      | ......####################......
        .byte   0,0                             | empty Pascal string ("Where:"), pad byte

| -------------------------------------------------------------------------
| ctlLogIcon (csCode 22), ctlPhysIcon (csCode 21), ctlDrvInfo (csCode 23)
| for floppy drives (csCode 23 also for HD20s), entered from the control
| dispatcher with CCR NE for a bad or missing drive
|   CSParam (out) -- pointer to the icon (icon, mask and an empty Pascal
|                    string), or the drive info word
| As in the 1987 SE driver, csCode 22 returns the diskette icon and csCode
| 21 the drive icon, as MTN #272 and Apple's SonyIcon.a have them (Inside
| Macintosh V-470 has them the other way round). Drive info: the drive
| type from DrvTbl, except 2 for an old-interface (400K) drive and 4 for
| a SuperDrive (new).
| -------------------------------------------------------------------------
SONY_CTL_MEDIAICON:
        BNE.B   SONY_CTL_ICONRET                | bad or missing drive -> return the error
        BSR.B   SONY_GETDRVTBL                  | getDrvTbl: A3 -> DrvTbl entry of this drive
        MOVE.W  (A3),D0                         | D0 = offset of the media icon
        MOVEA.L drvTblPtr(A1),A3                | A3 = drvTblPtr
        BCLR    #0x0,D0                         | bit 0: relative to the ROM table?
        BEQ.B   SONY_CTL_MEDIAICON_ADD          | no -> relative to drvTblPtr
        LEA.L   DRVTBL(PC),A3                   | A3 -> ROM DrvTbl
SONY_CTL_MEDIAICON_ADD:
        ADD.L   A3,D0                           | D0 = address of the icon
        BRA.B   SONY_CTL_PARAM                  | return it
SONY_CTL_DRIVEICON:
        BNE.B   SONY_CTL_ICONRET                | bad or missing drive -> return the error
        BSR.B   SONY_GETDRVTBL                  | getDrvTbl
        MOVE.W  0x2(A3),D0                      | D0 = offset of the drive icon
        MOVEA.L drvTblPtr(A1),A3                | A3 = drvTblPtr
        BCLR    #0x0,D0                         | bit 0: relative to the ROM table?
        BEQ.B   SONY_CTL_DRIVEICON_ADD          | no -> relative to drvTblPtr
        LEA.L   DRVTBL(PC),A3                   | A3 -> ROM DrvTbl
SONY_CTL_DRIVEICON_ADD:
        ADD.L   A3,D0                           | D0 = address of the icon
        BRA.B   SONY_CTL_PARAM                  | return it
SONY_CTL_DRVINFO:
        BNE.B   SONY_CTL_ICONRET                | bad or missing drive -> return the error
        BSR.B   SONY_GETDRVTBL                  | getDrvTbl
        MOVE.W  0x4(A3),D0                      | D0.L = drive info word (high word 0)
        CMPI.W  #0x4,Drive(A1)                  | HD20?
        BGE.B   SONY_CTL_PARAM                  | yes -> the table value
        TST.B   NewIntf(A1,D1.W)                | new-interface drive?
        BMI.B   SONY_CTL_DRVINFO_NEW            | yes -> check for a SuperDrive
        MOVE.B  #0x2,D0                         | old interface: drive type 2 (400K)
        BRA.B   SONY_CTL_PARAM                  | return it
SONY_CTL_DRVINFO_NEW:
        TST.B   mfmDrive(A1,D1.W)               | mfmDrive: SuperDrive?
        BPL.B   SONY_CTL_PARAM                  | no -> drive type 3 (800K) from the table
        MOVE.B  #0x4,D0                         | SuperDrive: drive type 4
| Branch from: SONY_CTL_MEDIAICON_ADD, SONY_CTL_DRIVEICON_ADD, SONY_CTL_DRVINFO, SONY_CTL_DRVINFO_NEW
SONY_CTL_PARAM:
        MOVE.L  D0,0x1C(A0)                     | CSParam = icon pointer or drive info
        MOVEQ.L #0x0,D0                         | noErr
SONY_CTL_ICONRET:
        BRA.W   SONY_TAIL_DISKDONE              | complete the request (DiskDone)
| getDrvTbl -- A3 -> DrvTbl entry (in the table drvTblPtr points to) of
| the physical drive behind the current logical drive (the drive number
| was checked by the dispatcher)
SONY_GETDRVTBL:
        MOVE.W  Drive(A1),D0                    | D0 = logical drive number
        ADD.W   D0,D0                           | * 2
        LEA.L   driveXlat(A1),A3                | A3 -> drive number translation table
        MOVE.W  0x0(A3,D0.W),D0                 | D0 = physical drive number
        SUBQ.W  #0x1,D0                         | - 1
        ADD.W   D0,D0                           | * 2
        MOVEA.W D0,A3                           | (save * 2)
        ADD.W   D0,D0                           | * 4
        ADD.W   A3,D0                           | * 6 = offset of the DrvTbl entry
        MOVEA.L drvTblPtr(A1),A3                | A3 = drvTblPtr
        ADDA.W  D0,A3                           | A3 -> entry of this drive
        RTS                                     | return
| SetDrvTbl -- drvTblPtr (SonyVars+$178) = DRVTBL; called by DiskOpen
| with A0 = SonyVars
SONY_SETDRVTBL:
        LEA.L   DRVTBL(PC),A2                   | A2 -> DrvTbl
        MOVE.L  A2,drvTblPtr(A0)                | drvTblPtr = DRVTBL
        RTS                                     | return
| complete the request: jump to DiskDone in the driver
SONY_TAIL_DISKDONE:
        JMP     (SONY_DRVENT_DISKDONE-BASEOFROM+0x400000).l | DiskDone

| -------------------------------------------------------------------------
| RAM-test patch (entry 13, $43D034), not part of the driver: the cold
| start code in boot/memtest.s jumps here instead of running the RAM test
| (test phase 14) directly, with A6 pointing to a word that holds the
| offset of P_CheckRamFirst8 relative to the word's end (= the return
| address MEMTEST_RAM_RET). The patch reads one long word from each of
| the four 1 MB RAM banks ($000000, $100000, $200000, $300000), sets
| D7 = 14 and jumps to P_CheckRamFirst8, which returns through A6.
| The purpose of the reads is not documented (no Apple source for this
| patch is known).
| -------------------------------------------------------------------------
FDHD_RAMTestPatch:
        MOVEA.W (A6)+,A0                        | A0 = offset; A6 = MEMTEST_RAM_RET (after the offset word)
        ADDA.L  A6,A0                           | A0 = P_CheckRamFirst8
        SUBA.L  A1,A1                           | A1 = 0: first RAM bank
        MOVE.W  #0x3,D1                         | four banks
FDHD_RAMTESTPATCH_LOOP:
        MOVE.L  (A1),D2                         | read a long word of this bank
        ADDA.L  #0x100000,A1                    | next 1 MB bank
        DBF     D1,FDHD_RAMTESTPATCH_LOOP       | all four
        MOVE.W  #0xE,D7                         | D7 = 14 (test phase, as in the SE)
        JMP     (A0)                            | RAM test, returns to MEMTEST_RAM_RET (A6)
| the initials string again from $3DD52 (in phase with the copy at
| $3CBA8: the patch code was written over the filled tail) up to $3FFED
ROMTail_Initials_FDHD_2:
    .ascii      "D "
    .rept       738
    .ascii      "SWC JSP GGD "
    .endr
    .ascii      "SW"

ROMTail_BuildDate_Tue_Oct_11_1988:
    .ascii      "Tue, Oct 11, 1988"             | build date
    .byte       0x11                            | last ROM byte

.endif
MacSEFDHD_ROM_End:
