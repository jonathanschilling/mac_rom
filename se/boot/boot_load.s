| Startup: boot from the startup disk (StartBoot)
|
| Apple source: StartBoot.a. BOOTME (MYBOOT in MacSEROM.lst) mounts the
| startup volume found by boot_search.s, reads the boot blocks, opens the
| System file, loads the patches and INITs, and launches the Finder (or
| the startup application). Also here: MOUSEINIT (mouse tracking
| parameters from parameter RAM), INITFS (_InitFS, File Manager startup)
| and INITEVENTS (_InitEvents, event queue).
|
| References: Inside Macintosh Vol IV, Ch 29 (startup); Mac Plus tree:
| boot/boot_load.s.

| ----------------------------------------------------------
| BOOTME - load and launch the System file from boot device
| A6 = boot block buffer (read by FINDSTARTUPDEVICE).
| Boot block format (Inside Macintosh Vol II):
|   +$06: version/flags (high byte $44 = call secondary boot code)
|   +$0A: System file name (16-byte Pascal string)
|   +$4A: Finder name (16-byte Pascal string)
|   +$7A: FS buffer config (word)
|   +$7C: event buffer count (word)
|   +$86: system heap size for 512K+ (long)
|   +$8C: heap base adjustment (long)
|   +$90: heap fraction multiplier (Fixed)
BOOTME:
    BSR.W       FINDSTARTUPDEVICE               | find and read boot device blocks
    MOVE.B      0x6(A6),D1                      | D1 = boot block version byte
    CMPI.B      #0x44,D1                        | version $44 (has secondary boot)?
    BEQ.B       CALL_SECONDARY_BOOT             | yes: call secondary boot code
    ANDI.B      #0xC0,D1                        | check bits 7-6
    CMPI.B      #0xC0,D1                        | both set ($C0+)?
    BNE.B       SELECT_HEAP_SIZE                | no: skip secondary boot
CALL_SECONDARY_BOOT:
    JSR         0x2(A6)                         | call secondary boot code in boot block
SELECT_HEAP_SIZE:
    MOVE.L      #0x18000,D0                     | D0 = default heap size (96K)
    MOVE.W      0x6(A6),D1                      | D1 = full version word
    CMPI.W      #0x14,D1                        | version <= $14 (old MFS disk)?
    BLS.B       USE_FIXED_HEAP                  | yes: use default heap size
    BTST        #0xF,D1                         | bit 15 set (fractional heap)?
    BEQ.B       USE_BOOT_HEAP                   | no: use boot block heap size
    BTST        #0xD,D1                         | bit 13 set (has multiplier)?
    BEQ.B       USE_BOOT_HEAP                   | no: use boot block heap size
| Fractional heap: size = SysZone + base + (MemTop * fraction)
    SUBQ.W      #0x4,A7                         | room for FracMul result
    MOVE.L      (MemTop).W,-(A7)                | push MemTop (total RAM)
    MOVE.L      0x90(A6),-(A7)                  | push fraction from boot block
    _FracMul                                    | result = MemTop * fraction
    MOVE.L      (A7)+,D0                        | D0 = fractional heap portion
    ADD.L       0x8C(A6),D0                     | add base adjustment
    MOVEA.L     (SysZone).W,A0                  | A0 = system zone base
    MOVEA.L     (A0),A0                         | A0 = zone limit (bkLim)
    ADDA.L      D0,A0                           | A0 = computed application base
    BRA.B       CAP_APPL_BASE                   | go cap at stack limit
USE_BOOT_HEAP:
    MOVE.L      0x86(A6),D0                     | D0 = 512K+ heap size from boot block
USE_FIXED_HEAP:
    MOVEA.L     (SysZone).W,A0                  | A0 = system zone base
    ADDA.L      D0,A0                           | A0 = SysZone + heap size
CAP_APPL_BASE:
    MOVEA.L     A7,A1                           | A1 = current SP
    SUBA.W      #0x2000,A1                      | A1 = SP - 8K (stack reserve)
    CMPA.L      A1,A0                           | appl base exceeds stack limit?
    BLS.B       SET_APPL_BASE2                  | no: use computed base
    MOVEA.L     A1,A0                           | yes: cap at stack limit
SET_APPL_BASE2:
    _SetApplBase                                | set application zone base
    MOVE.L      (SysZone).W,(TheZone).W         | switch to system zone for init
    MOVE.W      0x7C(A6),D0                     | D0 = event buffer count
    _InitEvents                                 | create event queue
    MOVE.W      0x7A(A6),D0                     | D0 = FS buffer config
    _InitFS                                     | initialize File System
| Mount the boot volume
    LEA.L       -0x400(A6),A0                   | A0 = IOParam block (below boot blocks)
    MOVE.W      (BootDrive).W,0x16(A0)          | ioVRefNum = boot drive number
    _MountVol                                   | mount the boot disk volume
    BNE.W       MOUNT_FAILED_EJECT              | mount failed: eject and retry
    CLR.L       0x12(A0)                        | ioFileName = nil (get by vRefNum)
    CLR.W       0x1C(A0)                        | ioVolIndex = 0
    _HGetVInfo                                  | get volume information
    BNE.B       COPY_SYSRES_NAME                | error: skip blessing check
    MOVEA.L     0x5E(A0),A4                     | A4 = blessed folder VRefNum
    MOVE.L      0x5A(A0),D0                     | D0 = blessed folder DirID
    BSR.W       SETVOL_BLESSED_FOLDER           | set up blessed folder
| Copy System resource name and open Finder
COPY_SYSRES_NAME:
    LEA.L       (SysResName).W,A1               | A1 = SysResName destination
    LEA.L       0xA(A6),A0                      | A0 = System name in boot block
    MOVEQ.L     #0x10,D0                        | D0 = 16 bytes (Pascal string)
    _BlockMove                                  | copy System name to low memory
    LEA.L       0x4A(A6),A1                     | A1 = Finder name in boot block
    MOVEQ.L     #0x1,D3                         | D3 = 1 (open for read)
    BSR.W       OPEN_AND_READ_FILE              | open Finder file
    SNE.B       D7                              | D7 = true if Finder open failed
    BNE.B       OPEN_SYSTEM_FILE                | failed: skip, try System file
| Draw startup bitmap from Finder icon to screen via CopyBits
    MOVE.L      #0x1560200,-(A7)                | push src bitmap: rows=342, rowBytes=512
    CLR.L       -(A7)                           | push src bitmap baseAddr = 0 (filled below)
    MOVE.W      (ScreenRow).W,-(A7)             | push screen row bytes (64)
    PEA.L       0x800(A6)                       | push src icon data (in boot blocks)
    LEA.L       -0x1FE(A6),A2                   | A2 = GrafPort storage
    MOVE.L      A7,-(A7)                        | push src bitmap ptr
    PEA.L       (A2)                            | push dst GrafPort
    PEA.L       0xE(A7)                         | push src rect
    PEA.L       0x6(A2)                         | push dst rect (portRect)
    CLR.W       -(A7)                           | push transfer mode = srcCopy
    CLR.L       -(A7)                           | push maskRgn = nil
    _CopyBits                                   | draw startup icon to screen
    ADDA.W      #0xE,A7                         | clean up src bitmap from stack
| ----------------------------------------------------------
| OPEN_SYSTEM_FILE - re-init resources, open System file
OPEN_SYSTEM_FILE:
    SUBQ.W      #0x2,A7                         | room for result
    CLR.L       (ResErrProc).W                  | no resource error handler
    _InitResources                              | re-init Resource Manager
    TST.W       (A7)+                           | check init result
    BPL.B       LOAD_DSAT_RESOURCE              | OK: continue loading
    LEA.L       -0x400(A6),A0                   | error: unmount and retry
    CLR.L       0x12(A0)                        | ioFileName = nil
    _UnmountVol                                 | unmount the failed volume
    JMP         MOUNT_FAILED_EJECT(PC)          | eject disk and retry boot
| ----------------------------------------------------------
| LOAD_DSAT_RESOURCE - load system error alert table ('DSAT' 0)
LOAD_DSAT_RESOURCE:
    SUBQ.W      #0x4,A7                         | room for Handle
    MOVE.L      #0x44534154,-(A7)               | push resource type 'DSAT'
    CLR.W       -(A7)                           | push resource ID 0
    _GetResource                                | load DSAT resource
    MOVE.L      (A7)+,D5                        | D5 = handle (saved for later release)
    BNE.B       GOT_DSAT                        | found: install it
    MOVEQ.L     #0x0,D7                         | not found: clear D7
    BRA.B       INIT_FONTS                      | skip DSAT installation
GOT_DSAT:
    MOVEA.L     D5,A0                           | A0 = DSAT handle
    MOVE.L      (A0),(DSAlertTab).W             | install alert table pointer
INIT_FONTS:
    _InitFonts                                  | initialize Font Manager
    MOVEQ.L     #0x28,D0                        | D0 = 40 (font cache size?)
    BSR.W       CHECK_BOOT_ERROR                | reserve font buffer space
| Reserve printer buffer below BufPtr
    MOVE.L      #0x600,D0                       | D0 = default print buf (1536 bytes)
    MOVE.W      0x8(A6),D1                      | D1 = boot block print buf field
    BEQ.B       RESERVE_STACK_BUF               | zero: skip print buffer
    BPL.B       RESERVE_PRINT_BUF               | positive: use D1 as size
    MOVEQ.L     #0x1,D0                         | negative: D0 = 0x8000
    ROR.W       #0x1,D0                         | D0 = 32768 (large print buffer)
RESERVE_PRINT_BUF:
    SUB.L       D0,(BufPtr).W                   | lower BufPtr by print buf size
RESERVE_STACK_BUF:
    SUBI.L      #0x400,(BufPtr).W               | lower BufPtr by 1K (stack reserve)
| Load and execute boot code patches from boot block names
    LEA.L       0x2A(A6),A1                     | A1 = boot patch 1 name
    BSR.W       OPEN_BOOT_PATCH                 | try to open patch 1
    BEQ.B       EXEC_PATCH1                     | found: execute it
    ADDI.L      #0x400,(BufPtr).W               | not found: reclaim 1K
    BRA.B       OPEN_SYSRES                     | skip patches
EXEC_PATCH1:
    JSR         (A1)                            | execute boot patch 1
    MOVEQ.L     #-0xA,D0                        | D0 = -10 (system error for patch fail)
    BSR.W       CHECK_BOOT_ERROR                | handle patch result
    LEA.L       0x3A(A6),A1                     | A1 = boot patch 2 name
    BSR.W       OPEN_BOOT_PATCH                 | try to open patch 2
    BNE.B       OPEN_SYSRES                     | not found: skip
    JSR         (A1)                            | execute boot patch 2
    MOVEQ.L     #-0xB,D0                        | D0 = -11 (system error for patch fail)
    BSR.W       CHECK_BOOT_ERROR                | handle patch result
| Open the System resource file
OPEN_SYSRES:
    LEA.L       (SysResName).W,A1               | A1 = System file name
    MOVEQ.L     #-0x1,D3                        | D3 = -1 (open resource fork)
    BSR.W       OPEN_AND_READ_FILE              | open System resource file
    BNE.B       LAUNCH_FINDER                   | error: skip to launch
    JSR         (A1)                            | execute System file init code
| ----------------------------------------------------------
| LAUNCH_FINDER - final boot: init ADB driver, mouse, launch app
LAUNCH_FINDER:
    BSR.W       INITADBDRVR                     | init ADB keyboard/mouse driver
    BSR.W       MOUSEINIT                       | init mouse tracking
    MOVE.L      D5,-(A7)                        | push DSAT handle
    _ReleaseResource                            | release DSAT resource
    MOVEQ.L     #0xC,D0                         | D0 = 12 bytes for AppParmHandle
    _NewHandleSysClear                          | allocate application parameter block
    MOVE.L      A0,(AppParmHandle).W            | store AppParmHandle
    _InitApplZone                               | initialize application heap zone
    _RDrvrInstall                               | install RAM-based drivers
    MOVEQ.L     #0x0,D6                         | D6 = 0 (first INIT resource ID)
| Load and execute INIT resources (IDs 0, 1, 2, ... until not found)
INIT_LOAD_LOOP:
    MOVEM.L     A5-A6,(BootTmp8)                | save A5-A6 across INIT execution
    SUBQ.W      #0x4,A7                         | room for Handle result
    MOVE.L      #0x494E4954,-(A7)               | push resource type 'INIT'
    MOVE.W      D6,-(A7)                        | push INIT resource ID
    _GetResource                                | load INIT resource
    MOVE.L      (A7)+,D7                        | D7 = INIT handle
    BEQ.B       INIT_LOAD_DONE                  | not found: done loading INITs
    MOVE.L      D7,-(A7)                        | push handle
    _DetachResource                             | detach so it stays in memory
    MOVEA.L     D7,A0                           | A0 = INIT handle
    MOVE.L      (A0),D0                         | D0 = INIT code pointer
    AND.L       (Lo3Bytes).W,D0                 | strip high byte (24-bit clean)
    MOVEA.L     D0,A0                           | A0 = INIT code address
    JSR         (A0)                            | execute INIT resource code
| INIT not found for this ID: restore regs, try next ID
INIT_LOAD_DONE:
    MOVEM.L     (BootTmp8),A5-A6                | restore A5-A6 after INIT execution
    ADDQ.W      #0x1,D6                         | D6 = next INIT resource ID
    CMPI.W      #0x24,D6                        | reached ID 36?
    BLT.B       INIT_LOAD_LOOP                  | no: try next INIT
| All INITs loaded: clean up and prepare to launch application
    PEA.L       -0x200(A6)                      | push GrafPort storage
    _ClosePort                                  | close boot-time GrafPort
    MOVEQ.L     #0x2,D0                         | D0 = 0x20000
    SWAP.W      D0                              | (128K purge threshold)
    _PurgeMemSys                                | purge system heap to free memory
| Send eject-on-boot-complete to disk driver
    LEA.L       -0x400(A6),A0                   | A0 = IOParam block
    MOVE.W      #0xFFFB,0x18(A7)                | ioRefNum = -5 (.Sony driver)
    MOVE.W      #0x9,0x1A(A0)                   | csCode = 9 (eject control)
    MOVE.W      #0xFF01,0x1C(A0)                | csParam = $FF01 (eject flags)
    _Control                                    | send eject control call
| Copy scrap and Finder names from boot block to low memory
    LEA.L       0x6A(A6),A0                     | A0 = scrap file name in boot block
    LEA.L       (ScrapTag).W,A1                 | A1 = ScrapTag destination
    MOVE.L      A1,(ScrapName).W                | ScrapName = ScrapTag address
    MOVEQ.L     #0x10,D0                        | 16 bytes (Pascal string)
    _BlockMove                                  | copy scrap file name
    LEA.L       0x1A(A6),A0                     | A0 = Finder name in boot block
    LEA.L       (FinderName).W,A1               | A1 = FinderName destination
    MOVEQ.L     #0x10,D0                        | 16 bytes (Pascal string)
    _BlockMove                                  | copy Finder name to low memory
    CLR.W       (CurApRefNum).W                 | no current application yet
| Determine boot volume for launch
    LEA.L       -0x400(A6),A0                   | A0 = IOParam block
    CLR.L       0x12(A0)                        | ioFileName = nil
    _GetVol                                     | get current default volume
    MOVE.W      0x16(A0),(BootDrive).W          | update BootDrive from default vol
    MOVE.L      A4,D0                           | D0 = blessed folder VRefNum
    BSR.W       SETVOL_BLESSED_FOLDER           | set up blessed folder
| Try to launch Finder or shell application
    LEA.L       0x5A(A6),A3                     | A3 = shell app name from boot block
    BSR.B       CHECK_FILE_EXISTS               | check if shell app exists
    BEQ.B       LAUNCH_APP                      | found: launch it
    LEA.L       0x1A(A6),A3                     | A3 = Finder name (fallback)
    BSR.B       CHECK_FILE_EXISTS               | check if Finder exists
    BNE.B       BOOT_FAIL                       | not found: fatal error
LAUNCH_APP:
    CLR.W       -(A7)                           | push launch flags = 0
    CLR.L       -(A7)                           | push reserved = 0
    MOVE.L      A3,-(A7)                        | push application name
    MOVEA.L     A7,A0                           | A0 = launch parameter block
    _Launch                                     | launch the application (never returns)
BOOT_FAIL:
    MOVEQ.L     #0x29,D0                        | D0 = 41 (dsFinderErr: can't find Finder)
    _SysError                                   | show system error dialog
    _Debugger                                   | drop into debugger (dead end)
| ----------------------------------------------------------
| MOUNT_FAILED_EJECT - boot volume mount failed: eject disk, retry
| Sends eject control to .Sony driver, clears the drive from
| BootMask, then jumps back to BOOTRETRY for next device.
MOUNT_FAILED_EJECT:
    LEA.L       -0x400(A6),A0                   | A0 = IOParam block
    MOVE.W      (BtDskRfn).W,0x18(A0)           | ioRefNum = boot disk driver refNum
    MOVE.W      #0x7,0x1A(A0)                   | csCode = 7 (eject)
    MOVE.W      (BootDrive).W,D3                | D3 = boot drive number
    MOVE.W      D3,0x16(A0)                     | ioVRefNum = drive number
    _Control                                    | eject the disk
    BNE.B       CLEAR_BOOT_MASK                 | control error: clear mask anyway
    CMPI.W      #0xFFFE,(BtDskRfn).W            | is it the built-in floppy?
    BNE.B       RETRY_BOOT                      | no: retry without mask change
CLEAR_BOOT_MASK:
    MOVE.W      (BootMask).W,D0                 | D0 = boot device mask
    BCLR        D3,D0                           | clear this drive from mask
    MOVE.W      D0,(BootMask).W                 | update mask (don't try again)
RETRY_BOOT:
    BRA.W       BOOTRETRY                       | restart boot sequence
| ----------------------------------------------------------
| CHECK_BOOT_ERROR - check boot error: if D7 != 0, call _SysError with D0
CHECK_BOOT_ERROR:
    TST.B       D7                              | was there a boot error?
    BEQ.B       CHECK_BOOT_ERROR_RTS            | no: return normally
    _SysError                                   | yes: show system error (D0 = err code)
CHECK_BOOT_ERROR_RTS:
    RTS                                         | return from CHECK_BOOT_ERROR
| ----------------------------------------------------------
|
| CHECK_FILE_EXISTS - File existence check - call _GetFileInfo on file named by A3
|
| Called during boot.
CHECK_FILE_EXISTS:
    LEA.L       -0x400(A6),A0                   | A0 = param block on stack
    CLR.W       0x16(A0)                        | ioVRefNum = 0 (default volume)
    CLR.L       0x1A(A0)                        | ioDirID = 0 (root directory)
    MOVE.L      A3,0x12(A0)                     | ioFileName = file name (from A3)
    _GetFileInfo                                | check if file exists (Z=success)
    RTS                                         | return from CHECK_FILE_EXISTS
| ----------------------------------------------------------
|
| OPEN_BOOT_PATCH - Open and read file (D3=0: from BufPtr) - entry for boot patch loading
|
| Called during boot.
OPEN_BOOT_PATCH:
    MOVEQ.L     #0x0,D3                         | D3 = 0: allocate from BufPtr
| Open file, read contents (D3 = alloc mode)
OPEN_AND_READ_FILE:
    LEA.L       -0x400(A6),A0                   | A0 = IOParam block on stack
    MOVEQ.L     #-0x1,D2                        | D2 = -1 (error sentinel)
    LEA.L       0x12(A0),A2                     | A2 -> ioFileName field
    MOVE.L      A1,(A2)+                        | Set file name
    CLR.L       (A2)+                           | Clear ioVRefNum + ioFileType
    CLR.B       (A2)+                           | Clear ioVersNum
    MOVE.B      #0x1,(A2)+                      | ioPermssn = fsRdPerm (read only)
    PEA.L       0x400(A6)                       | ioMisc = buffer for driver
    MOVE.L      (A7)+,(A2)                      | store ioMisc from stack
    _Open                                       | open the file
    BNE.B       FILE_LOAD_RETURN                | open failed: return error
    _GetEOF                                     | get file size -> ioMisc
    BNE.B       CLOSE_FILE                      | error: close and return
    MOVE.L      (A2)+,D4                        | D4 = file size (ioMisc)
    MOVEQ.L     #0x2,D6                         | D6 = 0x200 (512-byte header skip)
    ASL.W       #0x8,D6                         | D6 = 512
    SUB.L       D6,D4                           | D4 = data size (file - 512 header)
| Select allocation mode based on D3:
|   D3 = 0: allocate from BufPtr (boot patches)
|   D3 > 0: read into boot block buffer (Finder)
|   D3 < 0: allocate via _NewPtrSys (System file)
    TST.W       D3                              | check allocation mode
    BMI.B       ALLOC_SYS_PTR                   | negative: allocate system pointer
    BNE.B       ALLOC_BOOT_BUF                  | positive: use boot block buffer
    MOVEA.L     (BufPtr).W,A1                   | zero: allocate below BufPtr
    SUBA.L      D4,A1                           | A1 = BufPtr - data size
SETUP_READ_PARAMS:
    LEA.L       -0x400(A6),A0                   | A0 = IOParam block
    LEA.L       0x20(A0),A2                     | A2 = ioBuffer field
    MOVE.L      A1,(A2)+                        | ioBuffer = read destination
    MOVE.L      D4,(A2)+                        | ioReqCount = data size
    ADDQ.W      #0x4,A2                         | skip ioPosOffset
    MOVE.W      #0x1,(A2)+                      | ioPosMode = fsFromStart
    MOVE.L      D6,(A2)                         | ioPosOffset = 512 (skip header)
    _Read                                       | read file data
    BNE.B       CLOSE_FILE                      | read error: close file
    MOVEQ.L     #0x0,D2                         | D2 = 0 (success)
CLOSE_FILE:
    LEA.L       -0x400(A6),A0                   | A0 = IOParam block
    _Close                                      | close the file
FILE_LOAD_RETURN:
    MOVE.W      D2,D0                           | D0 = result (0=OK, -1=error)
    RTS                                         | return from OPEN_AND_READ_FILE
| ALLOC_BOOT_BUF - D3 > 0: read into boot block buffer area
ALLOC_BOOT_BUF:
    LEA.L       0x800(A6),A1                    | A1 = boot block buffer + 2K
    ADD.L       D6,D4                           | include 512 header in read
    MOVEQ.L     #0x0,D6                         | D6 = 0 (read from start of file)
    BRA.B       SETUP_READ_PARAMS               | go read
| ALLOC_SYS_PTR - D3 < 0: allocate system heap block for file data
ALLOC_SYS_PTR:
    MOVE.L      D4,D0                           | D0 = data size
    _NewPtrSys                                  | allocate block in system heap
    MOVE.W      D0,D2                           | D2 = error code
    BNE.B       CLOSE_FILE                      | alloc failed: close file
    MOVEA.L     A0,A1                           | A1 = allocated block
    BRA.B       SETUP_READ_PARAMS               | go read into allocated block
| ----------------------------------------------------------
| SETVOL_BLESSED_FOLDER - set default volume to blessed folder
| D0 = blessed folder DirID. If zero, returns immediately.
| Uses HFSDispatch selector 1 (SetVol by DirID) with the
| magic signature 'ERIK' to request folder-level SetVol.
SETVOL_BLESSED_FOLDER:
    TST.L       D0                              | blessed folder ID valid?
    BEQ.B       SETVOL_BLESSED_FOLDER_RTS       | zero: no blessed folder, skip
    LEA.L       -0x400(A6),A0                   | A0 = IOParam block
    MOVE.L      D0,0x30(A0)                     | ioDirID = blessed folder DirID
    CLR.L       0x12(A0)                        | ioFileName = nil
    MOVE.L      #0x4552494B,0x1C(A0)            | ioFileType = 'ERIK' (magic sig)
    MOVEQ.L     #0x1,D0                         | D0 = 1 (HFS selector: SetVol)
    _HFSDispatch                                | set vol to blessed folder
    BNE.B       SETVOL_BLESSED_FOLDER_RTS       | error: skip SetVol
    _SetVol                                     | make it the default volume
SETVOL_BLESSED_FOLDER_RTS:
    RTS                                         | return from SETVOL_BLESSED_FOLDER
| ----------------------------------------------------------
| MOUSEINIT - initialize mouse acceleration from PRAM and resources
| Reads mouse speed from SPVolCtl bits 5-3. If > 4, clamps to 2
| and updates PRAM. Loads 'mcky' resource for acceleration table.
MOUSEINIT:
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.B      (SPVolCtl).W,D0                 | D0 = PRAM volume/mouse byte
    LSR.B       #0x3,D0                         | D0 = mouse speed (bits 5-3)
    CMPI.B      #0x4,D0                         | speed <= 4 (valid)?
    BLE.B       LOAD_MCKY_RSRC                  | yes: use as-is
    MOVE.L      D3,-(A7)                        | save D3
    MOVE.W      #0x2,D0                         | clamp speed to 2
    MOVE.W      D0,D3                           | D3 = 2 (for PRAM update)
    ANDI.B      #0x7,(SPVolCtl).W               | clear mouse speed bits
    LSL.B       #0x3,D3                         | shift speed to bits 5-3
    OR.B        D3,(SPVolCtl).W                 | write clamped speed to PRAM
    MOVE.L      (A7)+,D3                        | restore D3
LOAD_MCKY_RSRC:
    SUBQ.W      #0x4,A7                         | room for Handle result
    MOVE.L      #0x6D636B79,-(A7)               | push resource type 'mcky'
    MOVE.W      D0,-(A7)                        | push resource ID = mouse speed
    _GetResource                                | load mouse acceleration table
    MOVE.L      (A7)+,D0                        | D0 = handle (or nil)
    BEQ.B       MOUSEINIT_DONE                  | not found: use ROM defaults
    MOVEA.L     D0,A0                           | A0 = handle
    MOVEA.L     (A0),A0                         | A0 = deref -> accel table data
    MOVEA.L     (MickeyBytes).W,A1              | A1 = mickey table in memory
    ADDA.W      #0x14,A1                        | A1 = offset $14 (accel params)
    MOVE.L      (A0)+,(A1)+                     | copy acceleration data word 1
    MOVE.L      (A0),(A1)                       | copy acceleration data word 2
MOUSEINIT_DONE:
    RTS                                         | return from MOUSEINIT
| ----------------------------------------------------------
| INITFS - initialize File System (HFS boot-time setup)
| Allocates FCB table, WDCB table, HFS stack, block cache buffers.
| D0 = number of file buffers (from boot block).
| Called via _InitFS trap during boot.
INITFS:
    TST.W       (FSFCBLen).W                    | already initialized (>= 0)?
    BPL.W       INITFS_OK                       | yes: return success
    MOVE.W      #0x5E,(FSFCBLen).W              | FCB entry size = 94 bytes (HFS)
    LEA.L       (CkdDB).W,A0                    | A0 = checked disk block table
    MOVEQ.L     #0x50,D1                        | 81 words to clear
CLEAR_CKDDB_LOOP:
    CLR.W       (A0)+                           | clear checked disk block entry
    DBF.W       D1,CLEAR_CKDDB_LOOP             | loop for all 81 entries
    MOVE.W      #0x2,(DrMstrBlk).W              | master directory block = sector 2
    CMPI.W      #0x2,(MemTop).W                 | RAM > 128K?
    BLE.B       INITFS_ALLOC_FCB                | no: use D0 as-is
    LSL.W       #0x2,D0                         | yes: quadruple buffer count
INITFS_ALLOC_FCB:
    MOVE.W      D0,D2                           | D2 = FCB count (save for WDCB calc)
    MULU.W      #0x5E,D0                        | D0 = FCB count * 94 bytes each
    ADDQ.W      #0x2,D0                         | +2 for length word at start
    MOVE.W      D0,D1                           | D1 = save total size
    _NewPtrSysClear                             | allocate FCB table
    BNE.W       INITFS_FAIL                     | alloc failed: return error
    MOVE.W      D1,(A0)                         | store FCB table size at start
    MOVE.L      A0,(FCBSPtr).W                  | FCBSPtr = FCB table pointer
| Allocate Working Directory Control Block table
    MULU.W      #0x10,D2                        | D2 = WDCB count * 16 bytes each
    MOVE.L      D2,D0                           | D0 = WDCB table size
    ADDQ.W      #0x2,D0                         | +2 for length word
    MOVE.W      D0,D1                           | D1 = save total size
    _NewPtrSysClear                             | allocate WDCB table
    BNE.W       INITFS_FAIL                     | alloc failed
    MOVE.W      D1,(A0)                         | store WDCB table size at start
    MOVE.L      A0,(WDCBsPtr).W                 | WDCBsPtr = WDCB table pointer
| Register WDCB table with Switcher context
    MOVEA.L     (SwitcherTPtr).W,A2             | A2 = Switcher context table
    MOVE.W      WDCBSWOS(PC),D0                 | D0 = WDCB switch-out offset
    MOVE.L      A0,0x0(A2,D0.W)                 | store WDCB ptr in context table
    NOT.L       0x0(A2,D0.W)                    | negate (Switcher convention)
    MOVE.W      D1,0x4(A2,D0.W)                 | store WDCB size in context table
| Allocate HFS stack (1296 bytes: 1280 stack + 16 header)
    MOVE.L      #0x510,D0                       | D0 = 1296 bytes
    _NewPtrSysClear                             | allocate HFS stack block
    BNE.B       INITFS_FAIL                     | alloc failed
    ADDA.W      #0x500,A0                       | A0 = top of 1280-byte stack
    MOVE.L      A0,(HFSVars_HFSStkTop).W        | store HFS stack top pointer
| Allocate PMSP (parameter block storage, 56 bytes)
    MOVEQ.L     #0x38,D0                        | D0 = 56 bytes
    _NewPtrSysClear                             | allocate PMSP block
    BNE.B       INITFS_FAIL                     | alloc failed
    MOVE.W      PMSPSWOS(PC),D0                 | D0 = PMSP switch-out offset
    MOVE.L      A0,0x0(A2,D0.W)                 | register with Switcher
    NOT.L       0x0(A2,D0.W)                    | negate (Switcher convention)
    ADDQ.L      #0x6,A0                         | skip 6-byte header
    MOVEQ.L     #0x32,D0                        | D0 = 50 (usable PMSP size)
    MOVE.W      D0,(A0)                         | store PMSP size
    MOVE.L      A0,(PMSPPtr).W                  | PMSPPtr = PMSP block
| Allocate block cache buffers (bitmap, volume, catalog)
    MOVE.W      #0x200,D1                       | D1 = 512 (block size)
    MOVEQ.L     #0x1,D0                         | D0 = 1 buffer
    JSR         (0x4094EE).L                    | allocate bitmap cache buffer
    BNE.B       INITFS_FAIL                     | alloc failed
    MOVE.L      A1,(SysBMCPtr).W                | SysBMCPtr = bitmap cache
    MOVEQ.L     #0x1,D0                         | D0 = 1 buffer (128K RAM)
    CMPI.W      #0x2,(MemTop).W                 | RAM > 128K?
    BLE.B       ALLOC_VOL_CACHE                 | no: 1 buffer
    MOVEQ.L     #0x2,D0                         | yes: 2 buffers
ALLOC_VOL_CACHE:
    JSR         (0x4094EE).L                    | allocate volume cache buffers
    BNE.B       INITFS_FAIL                     | alloc failed
    MOVE.L      A1,(SysVolCPtr).W               | SysVolCPtr = volume cache
    MOVEQ.L     #0x4,D0                         | D0 = 4 buffers (128K RAM)
    CMPI.W      #0x2,(MemTop).W                 | RAM > 128K?
    BLE.B       ALLOC_CTL_CACHE                 | no: 4 buffers
    MOVEQ.L     #0x10,D0                        | yes: 16 buffers
ALLOC_CTL_CACHE:
    JSR         (0x4094EE).L                    | allocate catalog cache buffers
    BNE.B       INITFS_FAIL                     | alloc failed
    MOVE.L      A1,(SysCtlCPtr).W               | SysCtlCPtr = catalog cache
    LEA.L       DSHOOK(PC),A0                   | A0 = disk-switch hook routine
    MOVE.L      A0,(DskSwtchHook).W             | install disk-switch handler
INITFS_OK:
    MOVEQ.L     #0x0,D0                         | D0 = 0 (success)
    RTS                                         | return from INITFS
| Called by: INITFS_ALLOC_FCB, ALLOC_VOL_CACHE, ALLOC_CTL_CACHE
INITFS_FAIL:
    MOVEQ.L     #-0x1,D0                        | D0 = -1 (error)
    RTS                                         | return from INITFS
| ----------------------------------------------------------
| INITEVENTS - initialize Event Manager (create event queue)
| D0 = number of event buffer slots (from boot block).
| Allocates D0 * 22 bytes, fills with $FFFF (free markers),
| and sets up the event queue header in low memory.
INITEVENTS:
    MOVE.W      D0,D2                           | D2 = event count (save)
    MOVEQ.L     #0x16,D0                        | D0 = 22 bytes per event record
    MULU.W      D2,D0                           | D0 = total buffer size
    MOVE.L      D0,D1                           | D1 = save size for fill loop
    _NewPtrSysClear                             | allocate event buffer
    LEA.L       (EvtBufCnt).W,A1                | A1 = EvtBufCnt (end of queue header)
    SUBQ.W      #0x1,D2                         | D2 = count - 1 (for DBF)
    MOVE.W      D2,(A1)                         | EvtBufCnt = event count - 1
    CLR.L       -(A1)                           | clear queue tail pointer
    CLR.L       -(A1)                           | clear queue head pointer
    CLR.W       -(A1)                           | clear queue flags
    MOVE.L      A0,-(A1)                        | store event buffer base pointer
| Fill event buffer with $FFFF (marks all slots as free)
FILL_EVTBUF_LOOP:
    NOT.W       (A0)+                           | write $FFFF to next word
    SUBQ.W      #0x2,D1                         | decrement byte counter
    BNE.B       FILL_EVTBUF_LOOP                | loop until buffer filled
    MOVE.W      #0xFFEF,-(A1)                   | SysEvtMask = all events except app4
    CLR.W       (KeyLast).W                     | no key pressed yet
    RTS                                         | return from INITEVENTS
