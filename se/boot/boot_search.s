| Startup: choosing the startup device (StartSearch)
|
| Apple source: StartSearch.a. FINDSTARTUPDEVICE walks the drive queue in
| the order set by the startup-device preference in extended parameter
| RAM (GETDEFAULTSTARTUP / SETDEFAULTSTARTUP, $A07D/$A07E) and the boot
| mask: floppy, HD20 or SCSI drives (ISITFLOPPY, ISITHD20, ISITSCSI ...),
| loading SCSI drivers (LOADDRIVERS), waiting for a disk (INTERNALWAIT,
| $A07F, with the wait-time settings GETTIMEOUT ... SETRAWTIMEOUT),
| reading the boot blocks (GETSTARTUPINFO), rejecting and ejecting disks,
| and the disk icons with question mark or X (SHOWDISKQ, SHOWDISKX,
| PLOTDISK, QMARK, XMARK).
|
| References: Inside Macintosh Vol V, Ch 25 (Start Manager, startup
| device); Technical Note on the startup device.

| ----------------------------------------------------------
| FINDSTARTUPDEVICE - find and select boot device
| Scans floppy and SCSI devices to find a bootable disk.
| State machine: search -> load drivers -> wait -> scan candidates
| -> select -> read boot blocks -> success or retry.
| Returns with boot blocks loaded in A6 buffer, BootDrive set.
FINDSTARTUPDEVICE:
    BSR.W       EMBARKONSEARCH                  | init search: read PRAM defaults
    BSR.W       LOADDRIVERS                     | load SCSI device drivers
    BSR.W       WAITFORINTERNAL                 | wait for internal floppy/SCSI
    BRA.B       SCAN_CANDIDATES                 | enter candidate scan loop
REPLAN_SEARCH:
    BSR.W       PLANSTRATEGY                    | adjust search order
    BSR.W       LOADDRIVERS                     | reload drivers if needed
RETRY_CANDIDATE:
    BSR.W       VISUALUPDATE                    | update boot progress display
SCAN_CANDIDATES:
    BSR.W       FINDNEXTCANDIDATE               | find next bootable device
    BEQ.B       REPLAN_SEARCH                   | none found: replan and retry
    BSR.W       SELECTDEVICE                    | select this device for boot
    BSR.W       CHECKMOUSEEJECT                 | check if user wants to eject
    BEQ.B       RETRY_CANDIDATE                 | ejected: try next candidate
    BSR.W       GETSTARTUPINFO                  | read boot blocks from device
    BEQ.B       BOOT_DEVICE_FOUND               | success: boot blocks loaded
    BSR.W       REACTTOFAILURE                  | handle read failure
    BRA.B       RETRY_CANDIDATE                 | try next candidate
BOOT_DEVICE_FOUND:
    BRA.W       SHOWSUCCESS                     | show happy Mac, continue boot
| ----------------------------------------------------------
| GETDEFAULTSTARTUP - read default startup device from XPRAM
| Reads 4 bytes from XPRAM offset $78 (startup device record).
GETDEFAULTSTARTUP:
    MOVE.L      #0x40078,D0                     | 4 bytes at XPRAM offset $78
    _ReadXPRam                                  | read startup device from XPRAM
    RTS                                         | return from GETDEFAULTSTARTUP
| ----------------------------------------------------------
| SETDEFAULTSTARTUP - write default startup device to XPRAM
SETDEFAULTSTARTUP:
    MOVE.L      #0x40078,D0                     | 4 bytes at XPRAM offset $78
    _WriteXPRam                                 | write startup device to XPRAM
    RTS                                         | return from SETDEFAULTSTARTUP
| ----------------------------------------------------------
| INTERNALWAIT - dispatch to boot-time wait subroutine by selector
| A0 = selector (0-9). Dispatches through DTAB_INTERNALWAIT
| jump table. Used by _InternalWait trap during boot.
INTERNALWAIT:
    MOVE.L      A0,D1                           | D1 = selector
    CMPI.W      #0x9,D1                         | selector > 9?
    BHI.B       INTERNALWAIT_RTS                | yes: invalid, return
    LSL.W       #0x1,D1                         | D1 = selector * 2 (word index)
    LEA.L       DTAB_INTERNALWAIT(PC),A1        | A1 = dispatch table base
    MOVE.W      0x0(A1,D1.W),D1                 | D1 = word offset to handler
    JSR         0x0(A1,D1.W)                    | call handler at table + offset
INTERNALWAIT_RTS:
    RTS                                         | return from INTERNALWAIT
| DTAB_INTERNALWAIT - jump table for _InternalWait selectors 0-9
| Each entry is a word offset from the table base to the handler.
DTAB_INTERNALWAIT:
    .short 0x02EE, 0x02F8                       | selectors 0, 1
    .short 0x0314, 0x031E                       | selectors 2, 3
    .short 0x0334, 0x0346                       | selectors 4, 5
    .short 0x0358, 0x036A                       | selectors 6, 7
| ----------------------------------------------------------
| EMBARKONSEARCH - initialize boot device search state
| Reads default startup device from XPRAM, sets up the candidate
| filter function (ISITFLOPORDEF for specific device, ISITANYTHING
| for any bootable device if no default is configured).
EMBARKONSEARCH:
    SUBQ.L      #0x4,A7                         | room for startup device record
    MOVEA.L     A7,A0                           | A0 = buffer
    _GetDefaultStartup                          | read XPRAM startup device
    MOVE.W      (A7)+,D3                        | D3 = default device ID
    MOVE.W      (A7)+,D4                        | D4 = default partition/flags
    SUBA.L      A2,A2                           | A2 = nil (no current candidate)
    LEA.L       ISITFLOPORDEF(PC),A3            | A3 = filter: floppy or default
    TST.W       D4                              | is a default device configured?
    BNE.B       EMBARK_SAVE_TIME                | yes: use ISITFLOPORDEF filter
    LEA.L       ISITANYTHING(PC),A3             | no default: accept any device
EMBARK_SAVE_TIME:
    MOVEA.L     (Ticks).W,A4                    | A4 = search start time
    CLR.W       D6                              | D6 = 0 (search state flags)
    RTS                                         | return from EMBARKONSEARCH
| ----------------------------------------------------------
| WAITFORINTERNAL - wait for internal floppy disk to become ready
| Polls drive queue for floppy insertion. Checks keyboard for
| Cmd-Opt-Shift-Delete (skip internal drive, $8805 in KeyMap).
| Times out after PRAM-configured seconds (default 15).
WAITFORINTERNAL:
    MOVEM.L     D5/A2,-(A7)                     | save D5/A2
    MOVEA.W     #0x2,A0                         | selector 2: check internal disk
    _InternalWait                               | check if internal drive ready
    ANDI.B      #0x80,D0                        | bit 7 = disk already inserted?
    BNE.B       WAITINT_DONE                    | yes: done waiting
    SUBA.L      A0,A0                           | selector 0: get wait timeout
    _InternalWait                               | D0 = timeout in seconds
    BNE.B       WAITINT_GOT_TIMEOUT             | non-zero: use it
    MOVE.W      #0xF,D0                         | default: 15 seconds
WAITINT_GOT_TIMEOUT:
    MULU.W      #0x3C,D0                        | D0 = timeout in ticks (60/sec)
    MOVE.L      D0,D5                           | D5 = deadline tick count
    MOVEA.W     #0x6,A0                         | selector 6: start wait
    _InternalWait                               | begin internal wait
WAITINT_POLL:
    MOVE.W      (KeyMap_6).W,D0                 | D0 = keyboard state
    CMPI.W      #0x8805,D0                      | Cmd-Opt-Shift-Delete pressed?
    BEQ.B       WAITINT_DONE                    | yes: user skips internal drive
    MOVEQ.L     #0x1,D0                         | D0 = 1 (check SCSI boot drives)
    JSR         SCSILOAD(PC)                    | any SCSI boot device ready?
    BEQ.B       WAITINT_CLEANUP                 | yes: stop waiting, use SCSI
    SUBA.L      A2,A2                           | A2 = nil (start of drive queue)
WAITINT_SCAN_DQ:
    BSR.W       NEXTDQENTRY                     | get next drive queue entry
    BEQ.B       WAITINT_CHECK_TIME              | end of queue: check timeout
    CMPI.W      #0xFFDF,0x8(A2)                 | drive number = internal floppy?
    BNE.B       WAITINT_SCAN_DQ                 | no: check next drive
    BRA.B       WAITINT_CLEANUP                 | yes: floppy found, stop waiting
WAITINT_CHECK_TIME:
    CMP.L       (Ticks).W,D5                    | timeout expired?
    BCC.B       WAITINT_POLL                    | no: keep polling
    MOVEA.W     #0x4,A0                         | selector 4: timeout notification
    _InternalWait                               | notify timeout
WAITINT_CLEANUP:
    MOVEA.W     #0x7,A0                         | selector 7: end wait
    _InternalWait                               | clean up wait state
WAITINT_DONE:
    MOVEM.L     (A7)+,D5/A2                     | restore D5/A2
    RTS                                         | return from WAITFORINTERNAL
| ----------------------------------------------------------
| LOADDRIVERS - load SCSI device drivers
| Checks keyboard for Cmd-Opt-Shift-Delete to skip SCSI drivers.
| D0 = -2 if skip requested, -1 for normal load.
LOADDRIVERS:
    MOVEQ.L     #-0x2,D0                        | D0 = -2 (skip SCSI drivers)
    MOVE.W      (KeyMap_6).W,D1                 | D1 = keyboard state
    CMPI.W      #0x8805,D1                      | Cmd-Opt-Shift-Delete?
    BEQ.B       LOADDRVR_CALL                   | yes: skip with D0 = -2
    MOVEQ.L     #-0x1,D0                        | no: load all (D0 = -1)
LOADDRVR_CALL:
    JSR         SCSILOAD(PC)                    | scan SCSI bus and load drivers
    RTS                                         | return from LOADDRIVERS
| ----------------------------------------------------------
| PLANSTRATEGY - adjust boot device search filter
| If default device is floppy ($FFFB), keep current filter.
| Otherwise, broaden to accept any bootable device.
PLANSTRATEGY:
    CMPI.W      #0xFFFB,D4                      | default device = floppy?
    BEQ.B       PLANSTRATEGY_RTS                | yes: keep ISITFLOPORDEF filter
    LEA.L       ISITANYTHING(PC),A3             | no: broaden to any device
PLANSTRATEGY_RTS:
    RTS                                         | return from PLANSTRATEGY
| ----------------------------------------------------------
| FINDNEXTCANDIDATE - find next bootable device in drive queue
| Walks drive queue via NEXTDQENTRY, skipping rejected drives
| (ISREJECT) and drives that don't match the filter (A3 callback).
| Returns Z=1 if no candidate found (A2=nil), Z=0 if found.
FINDNEXTCANDIDATE:
    BSR.W       NEXTDQENTRY                     | A2 = next drive queue entry
    BEQ.B       BOOT_FINDNEXT_DONE              | end of queue: no candidate
    BSR.W       ISREJECT                        | is this drive rejected?
    BEQ.B       FINDNEXTCANDIDATE               | yes: skip, try next
    JSR         (A3)                            | call filter (ISITFLOPORDEF etc.)
    BNE.B       FINDNEXTCANDIDATE               | filter rejected: try next
BOOT_FINDNEXT_DONE:
    MOVE.L      A2,D0                           | D0 = candidate (test for nil)
    RTS                                         | return from FINDNEXTCANDIDATE
| ----------------------------------------------------------
| NEXTDQENTRY - advance to next entry in drive queue
| A2 = current entry (nil = start from head). Returns next in A2.
| Z=1 if end of queue reached (A2=nil).
NEXTDQENTRY:
    MOVE.L      A2,D0                           | is A2 nil (first call)?
    BNE.B       NEXTDQ_FOLLOW                   | no: follow link
    MOVEA.L     (DrvQHdr_Head).W,A2             | yes: start from queue head
    BRA.B       NEXTDQ_TEST                     | test if head exists
NEXTDQ_FOLLOW:
    MOVEA.L     (A2),A2                         | A2 = next entry (qLink)
NEXTDQ_TEST:
    MOVE.L      A2,D0                           | D0 = entry (test for nil)
    RTS                                         | return from NEXTDQENTRY
| ----------------------------------------------------------
| SELECTDEVICE - set boot drive from selected drive queue entry
| A2 = drive queue entry. Sets ioRefNum, ioVRefNum, BtDskRfn, BootDrive.
SELECTDEVICE:
    LEA.L       -0x400(A6),A0                   | A0 = IOParam block
    MOVE.W      0x8(A2),D0                      | D0 = driver refNum from DQ entry
    MOVE.W      D0,0x18(A0)                     | ioRefNum = driver refNum
    MOVE.W      D0,(BtDskRfn).W                 | BtDskRfn = boot disk driver
    MOVE.W      0x6(A2),D0                      | D0 = drive number from DQ entry
    MOVE.W      D0,0x16(A0)                     | ioVRefNum = drive number
    MOVE.W      D0,(BootDrive).W                | BootDrive = this drive
    RTS                                         | return from SELECTDEVICE
| ----------------------------------------------------------
| CHECKMOUSEEJECT - if mouse button is down, eject the disk
| Returns Z=0 if disk was NOT ejected (boot can proceed).
CHECKMOUSEEJECT:
    TST.B       (MBState).W                     | mouse button state (bit 7=up)
    BMI.B       CHECKMOUSE_RTS                  | button up: no eject needed
    BSR.W       EJECTME                         | button down: eject disk
CHECKMOUSE_RTS:
    RTS                                         | return from CHECKMOUSEEJECT
| ----------------------------------------------------------
| GETSTARTUPINFO - read boot blocks (1K) from selected device
| Reads 1024 bytes from sector 0 into A6 buffer. Checks for
| boot signature 'LK' ($4C4B) at start of boot blocks.
| Returns Z=1 if valid boot blocks, Z=0 on error or bad signature.
GETSTARTUPINFO:
    MOVE.W      #0x1,0x2C(A0)                   | ioPosMode = fsFromStart
    CLR.L       0x2E(A0)                        | ioPosOffset = 0 (sector 0)
    MOVE.L      A6,0x20(A0)                     | ioBuffer = boot block buffer
    MOVE.L      #0x400,0x24(A0)                 | ioReqCount = 1024 bytes
    _Read                                       | read boot blocks
    BNE.B       GETSTARTUP_RTS                  | read error: return NZ
    CMPI.W      #0x4C4B,(A6)                    | check signature 'LK' (bootable)
GETSTARTUP_RTS:
    RTS                                         | return from GETSTARTUPINFO
| ----------------------------------------------------------
| REACTTOFAILURE - handle boot block read failure
| Error -65 ($FFBF): no disk in drive -- just return.
| Error -64 ($FFC0): offline -- mark as never-try-again.
| Other: eject disk, show failure icon.
REACTTOFAILURE:
    CMPI.W      #0xFFBF,D0                      | error -65 (noDriveErr)?
    BEQ.B       REACTFAIL_RTS                   | yes: silently skip
    CMPI.W      #0xFFC0,D0                      | error -64 (offlinErr)?
    BEQ.B       REACTFAIL_MARK                  | yes: mark as rejected
    BSR.W       EJECTME                         | other error: eject disk
    BEQ.B       REACTFAIL_SHOW                  | eject OK: show failure
REACTFAIL_MARK:
    BSR.W       NEVERAGAIN                      | mark drive as rejected
REACTFAIL_SHOW:
    BSR.W       SHOWDEVICEFAIL                  | show device failure icon
REACTFAIL_RTS:
    RTS                                         | return from REACTTOFAILURE
| ----------------------------------------------------------
| VISUALUPDATE - animate boot disk icon during device search
| Alternates between plain disk, disk-with-X (bad), and disk-with-?
| icons every 60 ticks (1 second) during the boot search loop.
| D6 bits: 8=initialized, 9=phase toggle, 10=X-flash enabled
VISUALUPDATE:
    BSET        #0x8,D6                         | first call? set initialized flag
    BEQ.B       VISUPD_RTS                      | first time: skip (no icon yet)
    CMPA.L      (Ticks).W,A4                    | time for next animation frame?
    BHI.B       VISUPD_RTS                      | not yet: skip
    MOVEA.L     (Ticks).W,A4                    | A4 = current time
    ADDA.W      #0x3C,A4                        | next frame in 60 ticks (1 sec)
    BCLR        #0xA,D6                         | X-flash enabled? clear it
    BEQ.B       VISUPD_TOGGLE                   | was not set: normal toggle
    MOVE.B      #0x3,D6                         | was set: show X for 3 frames
VISUPD_TOGGLE:
    BCHG        #0x9,D6                         | toggle animation phase
    BNE.B       VISUPD_FLASH                    | odd phase: X or ? icon
    BSR.W       SHOWPLAINDISK                   | even phase: show plain disk
    BRA.B       VISUPD_RTS                      | done
VISUPD_FLASH:
    TST.B       D6                              | X flash counter active?
    BEQ.B       VISUPD_QUESTION                 | no: show question mark
    BSR.W       SHOWDISKX                       | yes: show disk with X
    SUBQ.B      #0x1,D6                         | decrement X counter
    BRA.B       VISUPD_RTS                      | done
VISUPD_QUESTION:
    BSR.W       SHOWDISKQ                       | show disk with question mark
VISUPD_RTS:
    RTS                                         | return from VISUALUPDATE
| ----------------------------------------------------------
| ENABLEXFLASH - enable the X-flash animation on next cycle
ENABLEXFLASH:
    BSET        #0xA,D6                         | set X-flash flag in D6
    RTS                                         | return from ENABLEXFLASH
| ----------------------------------------------------------
| SHOWSUCCESS - display happy Mac icon (bootable disk found)
SHOWSUCCESS:
    _HideCursor                                 | hide cursor during icon draw
    MOVEM.L     A5-A6,-(A7)                     | save A5-A6
    LEA.L       SHOWSUCCESS_RET(PC),A6          | A6 = return address
    JMP         HAPPYMAC(PC)                    | draw happy Mac icon
SHOWSUCCESS_RET:
    MOVEM.L     (A7)+,A5-A6                     | restore A5-A6
    RTS                                         | return from SHOWSUCCESS
| ----------------------------------------------------------
| EJECTME - eject disk from currently selected drive
EJECTME:
    LEA.L       -0x400(A6),A0                   | A0 = IOParam block
    MOVE.W      #0x7,0x1A(A0)                   | csCode = 7 (eject)
    _Control                                    | eject disk
    RTS                                         | return from EJECTME
| ----------------------------------------------------------
| ISREJECT - check if drive should be rejected from boot search
| Returns Z=0 if drive is OK, Z=1 if rejected (not in BootMask
| or already tried and failed).
ISREJECT:
    BSR.W       INBOOTMASK                      | is this drive type bootable?
    BNE.B       ISREJECT_RTS                    | not bootable: reject (NZ)
    MOVE.W      0x6(A2),D1                      | D1 = drive number
    MOVE.W      (BootMask).W,D0                 | D0 = boot mask bitmap
    BTST        D1,D0                           | drive bit set in mask?
ISREJECT_RTS:
    RTS                                         | return from ISREJECT (Z=accepted)
| ----------------------------------------------------------
| ISITFLOPORDEF - filter: is this the default device or a floppy?
| Checks if drive matches XPRAM default (D4=refNum, D3=driveNum)
| or is the internal floppy ($FFFB).
ISITFLOPORDEF:
    CMP.W       0x8(A2),D4                      | driver refNum matches default?
    BNE.B       ISITFLOPPY                      | no: check if floppy
    CMPI.W      #0xFFFF,D3                      | default drive = any ($FFFF)?
    BEQ.B       ISITFLOPDEF_RTS                 | yes: match (any drive on this refNum)
    CMP.W       0x6(A2),D3                      | specific drive number matches?
    BNE.B       ISITFLOPPY                      | no: check if floppy
ISITFLOPDEF_RTS:
    RTS                                         | return Z=1 (match)
| ----------------------------------------------------------
| ISITFLOPPY - filter: is this a floppy drive? (refNum $FFFB)
ISITFLOPPY:
    CMPI.W      #0xFFFB,0x8(A2)                 | driver refNum = .Sony (-5)?
    RTS                                         | return Z=1 if floppy
| ISITHD20 - filter: is this an HD20? (refNum $FFFE)
ISITHD20:
    CMPI.W      #0xFFFE,0x8(A2)                 | driver refNum = HD20 (-2)?
    RTS                                         | return Z=1 if HD20
| ISITSCSI - filter: is this a SCSI device? (refNum $FFD8-$FFDF)
ISITSCSI:
    MOVE.W      0x8(A2),D0                      | D0 = driver refNum
    CMPI.W      #0xFFD8,D0                      | refNum >= -40 (SCSI ID 0)?
    BCS.B       ISITSCSI_NO                     | below range: not SCSI
    CMPI.W      #0xFFDF,D0                      | refNum <= -33 (SCSI ID 7)?
    BHI.B       ISITSCSI_NO                     | above range: not SCSI
    MOVEQ.L     #0x0,D0                         | D0 = 0 (clear, set Z=1)
ISITSCSI_NO:
    RTS                                         | return NZ (not SCSI)
| ISITANYTHING - filter: accept any drive (always returns Z=1)
ISITANYTHING:
    CMP.W       D0,D0                           | always equal (Z=1)
    RTS                                         | return Z=1 (always matches)
| ----------------------------------------------------------
| NEVERAGAIN - mark drive as rejected in BootMask
| Clears the drive's bit in BootMask so it won't be tried again.
NEVERAGAIN:
    BSR.W       INBOOTMASK                      | is this drive type in boot mask?
    BNE.B       NEVERAGAIN_RTS                  | not tracked: nothing to clear
    MOVE.W      0x6(A2),D1                      | D1 = drive number
    MOVE.W      (BootMask).W,D0                 | D0 = boot mask bitmap
    BCLR        D1,D0                           | clear this drive's bit
NEVERAGAIN_RTS:
    RTS                                         | return from NEVERAGAIN
| ----------------------------------------------------------
| INBOOTMASK - check if drive type is tracked in BootMask
| Returns Z=1 if floppy/HD20/SCSI with drive# <= 15, NZ otherwise.
INBOOTMASK:
    BSR.W       ISITFLOPPY                      | is it a floppy?
    BEQ.B       INBOOTMASK_CHK                  | yes: check drive number
    BSR.W       ISITHD20                        | is it HD20?
    BEQ.B       INBOOTMASK_CHK                  | yes: check drive number
    BSR.W       ISITSCSI                        | is it SCSI?
    BNE.B       INBOOTMASK_RTS                  | no: not tracked (NZ)
INBOOTMASK_CHK:
    CMPI.W      #0xF,0x6(A2)                    | drive number <= 15?
    BHI.B       INBOOTMASK_RTS                  | no: can't track in 16-bit mask
    MOVEQ.L     #0x0,D0                         | yes: tracked (Z=1)
INBOOTMASK_RTS:
    RTS                                         | return from INBOOTMASK
| ----------------------------------------------------------
| SHOWDEVICEFAIL - show failure indicator for failed boot device
| If it's a floppy, enable the X-flash animation.
SHOWDEVICEFAIL:
    BSR.W       ISITFLOPPY                      | is failed device a floppy?
    BNE.B       SHOWDEVFAIL_RTS                 | no: nothing to show
    BSR.W       ENABLEXFLASH                    | yes: start X-flash animation
SHOWDEVFAIL_RTS:
    RTS                                         | return from SHOWDEVICEFAIL
| ----------------------------------------------------------
| SHOWPLAINDISK / SHOWDISKQ / SHOWDISKX - draw boot disk icons
| SHOWPLAINDISK: draw plain disk (no overlay)
| SHOWDISKQ: draw disk with question mark overlay
| SHOWDISKX: draw disk with X mark overlay
SHOWPLAINDISK:
    SUBA.L      A0,A0                           | A0 = nil (no overlay icon)
    JMP         PLOTDISK(PC)                    | draw disk icon
SHOWDISKQ:
    LEA.L       QMARK(PC),A0                    | A0 = question mark bitmap
    JMP         PLOTDISK(PC)                    | draw disk with ?
SHOWDISKX:
    LEA.L       XMARK(PC),A0                    | A0 = X mark bitmap
    JMP         PLOTDISK(PC)                    | draw disk with X
| ----------------------------------------------------------
| PLOTDISK - draw disk icon with optional overlay to screen
| A0 = overlay bitmap (nil = none, QMARK or XMARK).
| Draws the disk icon at screen position $3FCB5E, then
| overlays the symbol (if any) at $3FCF1F.
PLOTDISK:
    MOVEM.L     D3-D7/A2-A6,-(A7)               | save all regs
    MOVE.L      A0,D7                           | D7 = overlay ptr (save)
    _HideCursor                                 | hide cursor during draw
    MOVE.L      (Ticks).W,D0                    | D0 = current tick
PLOTDISK_SYNC:
    CMP.L       (Ticks).W,D0                    | wait for tick change
    BEQ.B       PLOTDISK_SYNC                   | spin until next tick
    LEA.L       ICON_DISK(PC),A4                | A4 = disk icon bitmap
    MOVEA.L     #0x3FCB5E,A2                    | A2 = screen position for icon
    LEA.L       PLOTDISK_OVERLAY(PC),A6         | A6 = return address
    JMP         PUTICON(PC)                     | draw disk icon via PUTICON
| PLOTDISK_OVERLAY - overlay symbol on top of disk icon if needed
PLOTDISK_OVERLAY:
    TST.W       D7                              | overlay requested?
    BEQ.B       PLOTDISK_DONE                   | no: done
    MOVEA.L     #0x3FCF1F,A2                    | A2 = screen pos for symbol
    MOVEA.L     D7,A4                           | A4 = symbol bitmap data
    MOVEQ.L     #0xE,D2                         | D2 = 14 rows in symbol
    LEA.L       PLOTDISK_DONE(PC),A6            | A6 = return address
    JMP         PUTSYMBOL(PC)                   | draw symbol via PUTSYMBOL
PLOTDISK_DONE:
    _ShowCursor                                 | restore cursor
    MOVEM.L     (A7)+,D3-D7/A2-A6               | restore all regs
    RTS                                         | return from PLOTDISK
| QMARK - question mark bitmap (16x16, 30 bytes)
QMARK:
    .short      0x0000
    .long       0x000007E0, 0x0FF00C30
    .long       0x0C300070, 0x00E001C0
    .long       0x01800180, 0x00000180
    .long       0x01800000
| XMARK - X mark bitmap (16x16, 30 bytes)
XMARK:
    .long       0x00000000, 0x1008381C
    .long       0x1C380E70, 0x07E003C0
    .long       0x03C007E0, 0x0E701C38
    .long       0x381C1008
    .short      0x0000
| ICON_DISK - floppy disk icon bitmap (used during boot search)
| ICON_DISK bitmap data (26 bytes, floppy disk icon)
ICON_DISK:
    .short      0x007F
    .long       0xFFFFF5FE, 0xFFFEFF33
    .long       0x700FF807, 0xF703FFBB
    .long       0xF8709801, 0xFFFFFFFE
    .long       0xFF0007FF, 0xFFE00FFF
    .long       0xFFF0FFFF, 0xFFFFFFFF
    .long       0xFF0F77FF
    .short      0xFFEF
| ----------------------------------------------------------
| GETTIMEOUT - get boot wait timeout (low 5 bits of raw timeout)
GETTIMEOUT:
    JSR         GETRAWTIMEOUT(PC)               | read raw timeout byte from XPRAM
    ANDI.B      #0x1F,D0                        | mask to timeout value (0-31)
    RTS                                         | return from GETTIMEOUT
| ----------------------------------------------------------
| SETTIMEOUT - set boot wait timeout (low 5 bits, max 31)
SETTIMEOUT:
    MOVE.B      D0,-(A7)                        | save new timeout value
    JSR         GETRAWTIMEOUT(PC)               | read current raw byte
    MOVE.B      (A7)+,D1                        | D1 = new timeout
    CMPI.B      #0x1F,D1                        | clamp to max 31?
    BLS.B       SETTIMEOUT_MERGE                | no: use as-is
    MOVE.B      #0x1F,D1                        | yes: clamp to 31
SETTIMEOUT_MERGE:
    ANDI.B      #0xE0,D0                        | preserve flags (high 3 bits)
    OR.B        D1,D0                           | merge new timeout value
    JMP         SETRAWTIMEOUT(PC)               | write back to XPRAM
| ----------------------------------------------------------
| GETWAITFLAGS - get boot wait flags (high 3 bits of raw timeout)
GETWAITFLAGS:
    JSR         GETRAWTIMEOUT(PC)               | read raw timeout byte
    ANDI.B      #0xE0,D0                        | mask to flags only
    RTS                                         | return from GETWAITFLAGS
| ----------------------------------------------------------
| SETWAITFLAGS - set boot wait flags (high 3 bits)
SETWAITFLAGS:
    MOVE.B      D0,-(A7)                        | save new flags
    JSR         GETRAWTIMEOUT(PC)               | read current raw byte
    MOVE.B      (A7)+,D1                        | D1 = new flags
    ANDI.B      #0xE0,D1                        | mask to flags only
    ANDI.B      #0x1F,D0                        | preserve timeout value
    OR.B        D1,D0                           | merge new flags
    JMP         SETRAWTIMEOUT(PC)               | write back to XPRAM
| ----------------------------------------------------------
| DISABLEDYNWAIT - disable dynamic boot wait (set bit 7)
DISABLEDYNWAIT:
    MOVEA.W     #0x2,A0                         | selector 2: read status
    _InternalWait                               | read current boot wait status
    BSET        #0x7,D0                         | set "dynamic wait disabled" bit
    MOVEA.W     #0x3,A0                         | selector 3: write status
    _InternalWait                               | write updated status
    RTS                                         | return from DISABLEDYNWAIT
| ENABLEDYNWAIT - enable dynamic boot wait (clear bit 7)
ENABLEDYNWAIT:
    MOVEA.W     #0x2,A0                         | selector 2: read status
    _InternalWait                               | read current boot wait status
    BCLR        #0x7,D0                         | clear "dynamic wait disabled" bit
    MOVEA.W     #0x3,A0                         | selector 3: write status
    _InternalWait                               | write updated status
    RTS                                         | return from ENABLEDYNWAIT
| DISABLEPERMWAIT - disable permanent boot wait (set bit 6)
DISABLEPERMWAIT:
    MOVEA.W     #0x2,A0                         | selector 2: read status
    _InternalWait                               | read current boot wait status
    BSET        #0x6,D0                         | set "permanent wait disabled" bit
    MOVEA.W     #0x3,A0                         | selector 3: write status
    _InternalWait                               | write updated status
    RTS                                         | return from DISABLEPERMWAIT
| ENABLEPERMWAIT - enable permanent boot wait (clear bit 6)
ENABLEPERMWAIT:
    MOVEA.W     #0x2,A0                         | selector 2: read status
    _InternalWait                               | read current boot wait status
    BCLR        #0x6,D0                         | clear "permanent wait disabled" bit
    MOVEA.W     #0x3,A0                         | selector 3: write status
    _InternalWait                               | write updated status
    RTS                                         | return from ENABLEPERMWAIT
| ----------------------------------------------------------
| GETRAWTIMEOUT - read raw timeout byte from XPRAM offset $01
GETRAWTIMEOUT:
    CLR.B       -(A7)                           | push 1-byte buffer (zeroed)
    MOVEA.L     A7,A0                           | A0 = buffer on stack
    MOVE.L      #0x10001,D0                     | 1 byte at XPRAM offset $01
    _ReadXPRam                                  | read byte from XPRAM
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.B      (A7)+,D0                        | D0 = raw timeout byte
    RTS                                         | return from GETRAWTIMEOUT
| ----------------------------------------------------------
| SETRAWTIMEOUT - write raw timeout byte to XPRAM offset $01
SETRAWTIMEOUT:
    MOVE.B      D0,-(A7)                        | push byte to write
    MOVEA.L     A7,A0                           | A0 = buffer on stack
    MOVE.L      #0x10001,D0                     | 1 byte at XPRAM offset $01
    _WriteXPRam                                 | write byte to XPRAM
    MOVE.B      (A7)+,D0                        | restore D0
    RTS                                         | return from SETRAWTIMEOUT
