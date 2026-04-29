| Boot-time System Load and Manager Initialization (Plus-specific)
|
| Continuation of the boot sequence AFTER InitIOMgr completes. This file
| collects the Plus-specific boot-time system loader plus a handful of
| manager-init routines that physically live in the boot-area of the ROM:
|
| P_mGNEFilter - GetNextEvent filter (alarm-menu flash + ticks)
| DT_INITZONE_PARAMS / INIT_SYS_ZONE / REINIT_SYS_ZONE
| - SysZone (system heap) initialization
| BootFromDisk - top of the system-loading state machine
| (heap sizing, System file open, resource map reopen,
| font-buffer reservation, LAUNCH_APP dispatch)
| InitFS - File Manager boot-time init (FCB/VCB cache setup)
| InitEvents - Event Manager boot-time init (event queue buffers)
|
| There is no direct equivalent in the 128K/512K (original) tree; the
| classic ROM's boot path is simpler and lives entirely inside
| src/original/boot/vectors.s. These routines are Plus-specific additions
| that drive HFS-aware boot, System-file load, and the launch of the
| Finder.
|
| References: Inside Macintosh Vol I (Boot), Vol II (File Manager),
| Vol V (System-Launch changes).

| ----------------------------------------------------------
|
| P_m GNE Filter
|
| Called during boot (3,695 times in 30s trace).
P_mGNEFilter:
        LEA.L   (AlarmState).w,A1               | A1 = AlarmState low-memory address
        BSET    #0x5,(A1)                       | Set 'GNE filter ran' bit
        BNE.B   GNE_FILTER_DONE                 | Already set: skip alarm check
        MOVEQ.L #0x3,D0                         | D0 = alarm mask (bits 0-1)
        AND.B   (A1),D0                         | Check if alarm is armed/active
        BNE.B   GNE_FILTER_DONE                 | Alarm not ready: skip
        TST.B   (WWExist).w                     | Window Manager initialized?
        BNE.B   GNE_FILTER_DONE                 | Not yet: skip alarm display
        MOVE.L  (MenuList).w,D0                 | D0 = MenuList handle
        BEQ.B   GNE_FILTER_DONE                 | No menus: skip alarm display
        MOVE.L  D0,A0                           | A0 = deref MenuList handle
        MOVE.L  (A0),A0                         | A0 = deref again (master ptr)
        TST     (A0)                            | Any menus in menu bar?
        BLE.B   GNE_FILTER_DONE                 | No menus: skip
        MOVE.L  0x6(A0),A0                      | A0 = first menu handle
        MOVE.L  (A0),A0                         | A0 = deref menu handle
        CMPI    #0x114,0xE(A0)                  | Apple menu width = 0x114 (276 pixels)?
        BNE.B   GNE_FILTER_DONE                 | Wrong width: skip alarm flash
        MOVE.L  #0x10011,-(SP)                  | Push shield rect top-left (1,17)
        MOVE.L  #0x13001E,-(SP)                 | Push shield rect bot-right (19,30)
| Flash the Apple menu bar area (alarm indicator) by XORing scanlines.
| A1 = AlarmState low-memory address (set by caller).
        MOVE.L  (JShieldCursor).w,A0            | Shield cursor from drawing
        JSR     (A0)                            | Call JShieldCursor
        MOVE.L  (ScrnBase).w,A0                 | A0 = screen base
        MOVE    (ScreenRow).w,D0                | D0 = 64 (bytes per scanline)
        MOVE.L  #0x7FFC,D1                      | XOR mask: flip bits 2-14 of first long
        MOVEQ.L #0x11,D2                        | 18 scanlines (menu bar height)
| XOR Apple menu area (alarm flash)
ALARM_FLASH_LOOP:
        ADDA    D0,A0                           | Advance to next scanline
        EOR.L   D1,(A0)                         | XOR first 4 bytes (Apple logo area)
        DBF     D2,ALARM_FLASH_LOOP             | Loop 18 scanlines
        MOVE.L  (JShowCursor).w,A0              | Restore cursor
        JSR     (A0)                            | Call JShowCursor
        BCHG    #0x7,(A1)                       | Toggle alarm flash state
        BCLR    #0x6,(A1)                       | Clear "alarm triggered" bit
        BEQ.B   GNE_FILTER_DONE                 | Not triggered: return quietly
        MOVE    #0x8,-(SP)                      | Push duration = 8
        _SysBeep                                | Sound the alarm beep
| Return from GNEFilter
GNE_FILTER_DONE:
        RTS                                     | Return from GNEFilter

| DT_INITZONE_PARAMS - InitZone parameter block (28 bytes)
| Configures the initial system heap zone: start, limit, grow proc, master count.
| Fields: Lo3Bytes mask, startPtr, limitPtr, cMoreMasters, pGrowZone, etc.
DT_INITZONE_PARAMS:
  .byte 0x00,0xFF,0xFF,0xFF,0x00,0x00           | Lo3Bytes mask (0x00FFFFFF), startPtr hi
  .byte 0x04,0x00,0x00,0x00,0x20,0x00           | startPtr=0x0400, limitPtr hi=0x0000, lo=0x2000
  .byte 0x00,0x00,0x00,0x00,0x14,0x00           | cMoreMasters=0, pGrowZone=0, cbMasters=20
  .byte 0x00,0x00,0x4E,0x00,0x00,0x20           | reserved, flags=0x4E00, heap ID=0x0020
  .byte 0x00,0x00,0x00,0x00                     | reserved (28 bytes total)

| INIT_SYS_ZONE - initialize system heap zone from DT_INITZONE_PARAMS parameters
| Copies DT_INITZONE_PARAMS data to low-memory zone config area, then calls _InitZone.
INIT_SYS_ZONE:
        LEA.L   DT_INITZONE_PARAMS(PC),A0       | A0 = InitZone parameter template
        LEA.L   (Lo3Bytes).w,A1                 | A1 = destination (low-mem config area)
        MOVEQ.L #0x6,D0                         | Copy 7 words (14 bytes)
| Copy InitZone parameter words
COPY_ZONE_PARAMS:
        MOVE    (A0)+,(A1)+                     | Copy parameter word
        DBF     D0,COPY_ZONE_PARAMS             | Copy next parameter word
        _InitZone                               | Create the system heap zone
        MOVE.L  (TheZone).w,(SysZone).w         | SysZone = newly created system zone
        RTS                                     | Return from INIT_SYS_ZONE (zone init)

| REINIT_SYS_ZONE - alternate zone init entry (used during warm restart)
REINIT_SYS_ZONE:
        _InitZone                               | Re-create system heap zone
        MOVE.L  (TheZone).w,(SysZone).w         | Update SysZone pointer
        RTS                                     | Return from REINIT_SYS_ZONE (zone re-init)

| === BootFromDisk: load and launch the System file ===
| A6 = buffer containing boot blocks (1024 bytes read from disk sector 0).
| Boot block format (Inside Macintosh Vol II, pp 120-121):
| +$00: signature ($4C4B = bootable)
| +$02: entry point for secondary boot code
| +$06: version/flags (high byte $44 = call entry point)
| +$0A: System file name (16-byte Pascal string)
| +$4A: Shell application name (for Finder)
| +$7A: event buffer size (word)
| +$7C: system heap size for 128K config (long)
| +$7E: system heap size for 128K config (long, duplicated)
| +$86: system heap size for 512K+ config (long)
| Called during boot.
BootFromDisk:
        CMPI.B  #0x44,0x6(A6)                   | Boot block version $44xx?
        BNE.B   SKIP_SECONDARY_BOOT             | No: skip secondary boot code
        JSR     0x2(A6)                         | Call secondary boot code in boot block
| Select 128K or 512K heap size
SKIP_SECONDARY_BOOT:
        CMPI    #0x14,0x6(A6)                   | Version <= $14 (old MFS disk)?
        BHI.B   SELECT_HEAP_SIZE                | No: use boot block's heap size
        MOVE.L  #0xB700,0x86(A6)                | Override 512K heap size to 46848 bytes

| Select system heap size based on installed RAM
SELECT_HEAP_SIZE:
        MOVE.L  0x7E(A6),D0                     | D0 = 128K config heap size
        CMPI    #0x2,(MemTop).w                 | MemTop <= 0x20000 (128K)?
        BLE.B   SET_APPL_BASE                   | Yes: use 128K heap size
        MOVE.L  0x86(A6),D0                     | No: use 512K+ heap size
| Set app base, init events/FS, mount volume
SET_APPL_BASE:
        MOVE.L  (SysZone).w,A0                  | A0 = system zone start
        ADDA.L  D0,A0                           | A0 = system zone start + heap size
        _SetApplBase                            | Set application zone boundary
        MOVE.L  (SysZone).w,(TheZone).w         | Switch to system zone for init
| Initialize Event Manager and File System from boot block parameters
        MOVE    0x7C(A6),D0                     | D0 = event buffer count
        _InitEvents                             | Create event queue
        MOVE    0x7A(A6),D0                     | D0 = FS buffer config
        _InitFS                                 | Initialize File System
| Mount the boot volume
        MOVE.L  A7,A0                           | A0 = IOParam block (on stack)
        MOVE    (BootDrive).w,ioVRefNum(A0)     | Set boot drive number
        _MountVol                               | Mount the boot disk volume
        BNE     MOUNT_FAILED_EJECT              | Mount failed: eject and retry
| Get volume info to find the Finder info (blessing)
        CLR.L   ioFileName(A0)                  | No filename (get by vRefNum)
        CLR     0x1C(A0)                        | ioVolIndex = 0
        _HGetVInfo                              | Get volume information
        BNE.B   COPY_SYSRES_NAME                | Error: skip Finder info
        MOVE.L  0x5E(A0),A4                     | A4 = Finder info from volume
        MOVE.L  0x5A(A0),D0                     | D0 = volume attributes
        BSR     SET_BLESSED_VOLUME              | Process volume Finder info
| Copy System name, open Finder
COPY_SYSRES_NAME:
| Copy System file name from boot block to SysResName low-memory
        LEA.L   (SysResName).w,A1               | Destination: System file name
        LEA.L   0xA(A6),A0                      | Source: boot block +$0A (System name)
        MOVEQ.L #0x10,D0                        | 16 bytes (Pascal string)
        _BlockMove                              | Copy System file name
| Open the shell application (Finder) specified in boot block
        LEA.L   0x4A(A6),A1                     | A1 = Finder name from boot block (+$4A)
        MOVEQ.L #0x1,D3                         | D3 = 1 (open flag)
        BSR     OPEN_AND_READ_FILE              | Open Finder application
        SNE.B   D7                              | D7 = -1 if Finder open failed
        BNE.B   REOPEN_RESOURCES                | Failed: skip Welcome bitmap
| Draw "Welcome to Macintosh" bitmap from boot block
| The bitmap is at boot block +$800, 342 rows x 2 bytes = 684 bytes.
        MOVE.L  #0x1560200,-(SP)                | Source bounds: 342 rows, 512 wide
        CLR.L   -(SP)                           | Source top-left = (0,0)
        MOVE    (ScreenRow).w,-(SP)             | Dest row bytes = 64
        PEA.L   0x800(A6)                       | Source data pointer (boot block +$800)
        LEA.L   -0x1FE(A6),A2                   | Dest rect workspace
        MOVE.L  A7,-(SP)                        | Push source BitMap address
        PEA.L   (A2)                            | Push dest BitMap address
        PEA.L   0xE(SP)                         | Push source rect
        PEA.L   0x6(A2)                         | Push dest rect
        CLR     -(SP)                           | Mode = srcCopy
        CLR.L   -(SP)                           | MaskRgn = nil
        _CopyBits                               | Blit "Welcome to Macintosh" to screen
        ADDA    #0xE,SP                         | Clean up BitMap structures from stack
| Re-open resources, load DSAT
REOPEN_RESOURCES:
        SUBQ.W  #0x2,SP                         | Make room for InitResources result
        CLR.L   (ResErrProc).w                  | Clear resource error procedure
        _InitResources                          | Re-open system resource file
        TST     (SP)+                           | Check result
        BMI     MOUNT_FAILED_EJECT              | fail| eject disk and wait for a new one
| Load the system error alert table ('DSAT' resource ID 0)
        SUBQ.W  #0x4,SP                         | Room for Handle result
        MOVE.L  #0x44534154,-(SP)               | Resource type 'DSAT'
        CLR     -(SP)                           | Resource ID 0
        _GetResource                            | Load system error alert table
        MOVE.L  (SP)+,D5                        | D5 = DSAT handle (saved for later release)
        BEQ     DSAT_NOT_FOUND                  | Not found: skip to error handling
        MOVE.L  D5,A0                           | A0 = DSAT handle (deref for alert table)
        MOVE.L  (A0),(DSAlertTab).w             | DSAlertTab = *DSAT (alert definitions)
| Initialize Font Manager and allocate system buffers
INIT_FONTS_BUFS:
        _InitFonts                              | Initialize Font Manager (loads system font)
        MOVEQ.L #0x28,D0                        | D0 = 40
        BSR     CHECK_BOOT_ERROR                | Allocate 40-byte system buffer
| Allocate printer buffer space from BufPtr based on boot block config
        MOVE.L  #0x600,D0                       | Default printer buffer = 1536 bytes
        MOVE    0x8(A6),D1                      | Boot block +$08: printer config
        BEQ.B   RESERVE_TAG_BUF                 | Zero: no printer buffer needed
        BPL.B   RESERVE_PRINT_BUF               | Positive: use D0 as size
        MOVEQ.L #0x1,D0                         | Negative: use 32768 (half of 64K)
        ROR     #0x1,D0                         | D0 = 0x8000 = 32768
| Subtract printer buffer from BufPtr
RESERVE_PRINT_BUF:
        SUB.L   D0,(BufPtr).w                   | Reserve space from top of buffer area
| Reserve tag buffer, run boot patches
RESERVE_TAG_BUF:
        SUBI.L  #0x400,(BufPtr).w               | Reserve 1024 bytes for disk tag buffer

| Execute boot block patch code entries (offsets +$2A and +$3A)
| These are optional patches applied during boot before launching the System.
        LEA.L   0x2A(A6),A1                     | Boot block +$2A: first patch name
        BSR     OPEN_BOOT_PATCH                 | Load and prepare patch code
        BNE     PATCH_LOAD_FAILED               | Error: abort boot
        JSR     (A1)                            | Execute first patch
        MOVEQ.L #-0xA,D0                        | D0 = -10
        BSR     CHECK_BOOT_ERROR                | Adjust system buffer
        LEA.L   0x3A(A6),A1                     | Boot block +$3A: second patch name
        BSR     OPEN_BOOT_PATCH                 | Load and prepare patch code
        BNE.B   OPEN_SYSTEM_RSRC                | Not found: skip
        JSR     (A1)                            | Execute second patch
        MOVEQ.L #-0xB,D0                        | D0 = -11
        BSR     CHECK_BOOT_ERROR                | Adjust system buffer
| Open the System file as a resource file
OPEN_SYSTEM_RSRC:
        LEA.L   (SysResName).w,A1               | A1 = System file name
        MOVEQ.L #-0x1,D3                        | D3 = -1 (open for resource access)
        BSR     OPEN_AND_READ_FILE              | Open System resource file
        BNE     PREPARE_LAUNCH                  | Error: skip resource init
        JSR     (A1)                            | Call System init code (if any)
| Prepare to launch the Finder application
PREPARE_LAUNCH:
        MOVE.L  (SysZone).w,(RAMBase).w         | RAMBase = system zone (finalized)
        MOVEQ.L #0xC,D0                         | 12 bytes for AppParmHandle
        _NewHandleSysClear                      | Allocate in system heap
        MOVE.L  A0,(AppParmHandle).w            | Store app parameter handle
        _InitApplZone                           | Create the application heap zone
        _RDrvrInstall                           | Install RAM-based drivers
        MOVE.L  D5,-(SP)                        | Push DSAT handle
        _ReleaseResource                        | Release the alert table resource

| === Execute INIT resources (system extensions) ===
| Load and execute 'INIT' resources 0 through 35 ($24).
| These are startup code from the System file and extensions.
        MOVEQ.L #0x0,D6                         | D6 = INIT resource ID counter
| INIT load/execute loop (IDs 0-35)
INIT_LOAD_LOOP:
        MOVEM.L A5-A6,(BootTmp8).w              | Save globals across INIT execution
        SUBQ.W  #0x4,SP                         | Room for Handle result
        MOVE.L  #0x494E4954,-(SP)               | Resource type 'INIT'
        MOVE    D6,-(SP)                        | Resource ID = D6
        _GetResource                            | Load INIT resource
        MOVE.L  (SP),D7                         | D7 = handle (nil if not found)
        BEQ     INIT_NOT_FOUND                  | Not found: skip to next ID
        _DetachResource                         | Detach so it stays in memory
        MOVE.L  D7,A0                           | A0 = handle
        MOVE.L  (A0),D0                         | D0 = *handle (pointer)
        AND.L   (Lo3Bytes).w,D0                 | Strip flags (24-bit address)
        MOVE.L  D0,A0                           | A0 = clean code pointer
        JSR     (A0)                            | Execute the INIT resource
| Restore globals after INIT, try next
INIT_NEXT:
        MOVEM.L (BootTmp8).w,A5-A6              | Restore globals
        ADDQ.W  #0x1,D6                         | Next INIT ID
        CMPI    #0x24,D6                        | Tried all 36 INITs?
        BLT.B   INIT_LOAD_LOOP                  | No: try next one

| === Boot cleanup: purge memory, close boot port, set speaker volume ===
        MOVEQ.L #0x2,D0                         | D0 = 0x20000 (128K)
        SWAP    D0                              | D0 = 0x20000 (128K purge amount)
        _PurgeMemSys                            | Purge system heap (free INIT memory)
        PEA.L   -0x200(A6)                      | Push boot GrafPort address
        _ClosePort                              | Close the boot GrafPort
| Set speaker volume from PRAM via .Sound driver control call
        LEA.L   -0x400(A6),A0                   | A0 = control param block on stack
        MOVE    #-0x5,ioRefNum(SP)              | Driver refNum = -5 (.Sound)
        MOVE    #0x9,0x1A(A0)                   | csCode = 9 (set volume)
        MOVE    #-0xFF,0x1C(A0)                 | csParam = volume from PRAM
        _Control                                | Set speaker volume
| Set up Scrap Manager (clipboard) and copy Finder name from boot block
        LEA.L   (ScrapTag).w,A1                 | A1 = scrap file name buffer
        MOVE.L  A1,(ScrapName).w                | ScrapName -> scrap tag location
        LEA.L   0x6A(A6),A0                     | Boot block +$6A: scrap file name
        MOVEQ.L #0x10,D0                        | 16 bytes (Pascal string)
        _BlockMove                              | Copy scrap file name
        LEA.L   0x1A(A6),A0                     | Boot block +$1A: Finder name
        LEA.L   (FinderName).w,A1               | Destination: FinderName low-mem
        MOVEQ.L #0x10,D0                        | 16 bytes
        _BlockMove                              | Copy Finder name ("Finder")
        CLR     (CurApRefNum).w                 | No application resource file yet
        MOVE.L  A4,D0                           | D0 = Finder info from volume
        BSR     SET_BLESSED_VOLUME              | Process Finder directory info

| === Launch the initial application (startup app or Finder) ===
| Try the startup application first (boot block +$5A), fall back to Finder.
        LEA.L   0x5A(A6),A3                     | A3 = startup app name from boot block
        BSR.B   CHECK_FILE_EXISTS               | Find the startup application
        BEQ.B   LAUNCH_APP                      | Found: launch it
        LEA.L   0x1A(A6),A3                     | A3 = Finder name from boot block
        BSR.B   CHECK_FILE_EXISTS               | Find the Finder
        BNE.B   LAUNCH_FAILED                   | Not found: fatal error
| LAUNCH_APP - launch the application (A3 = name of app to launch)
LAUNCH_APP:
        MOVE.L  A7,A0                           | A0 = param block on stack
        CLR.L   ioFileName(A0)                  | No file name (use default volume)
        _GetVol                                 | Get current volume info
        MOVE    ioVRefNum(A0),(BootDrive).w     | Update boot drive from volume
        CLR     -(SP)                           | Push 0 (no launch flags)
        CLR.L   -(SP)                           | Push nil (no alternateEvtMask)
        MOVE.L  A3,-(SP)                        | Push app name string
        MOVE.L  A7,A0                           | A0 = launch param block
        _Launch                                 | === LAUNCH THE FINDER ===
| If we get here, _Launch returned - that means it failed.
LAUNCH_FAILED:
        MOVEQ.L #0x29,D0                        | dsFinderErr (41): can't load Finder
        _SysError                               | Show system error dialog
        _Debugger                               | Drop into ROM debugger
| INIT_NOT_FOUND - INIT resource not found: skip and try next ID
INIT_NOT_FOUND:
        ADDQ.W  #0x4,SP                         | Clean nil handle from stack
        BRA     INIT_NEXT                       | Continue INIT loop

| MOUNT_FAILED_EJECT - disk mount failed: eject and return to WaitForBootDisk
MOUNT_FAILED_EJECT:
        LEA.L   -0x400(A6),A0                   | A0 = control param block
        MOVE    (BtDskRfn).w,0x18(A0)           | Set disk driver refNum
        MOVE    #0x7,0x1A(A0)                   | csCode = 7 = eject
        MOVE    (BootDrive).w,D3                | D3 = boot drive number
        MOVE    D3,0x16(A0)                     | Set drive for control call
        _Control                                | Eject the failed disk
        BEQ.B   EJECT_WARM_RESTART              | Eject OK: warm restart
        MOVE    (BootMask).w,D0                 | Eject failed: update boot mask
        BCLR    D3,D0                           | Remove this drive from mask
        MOVE    D0,(BootMask).w                 | Save updated boot mask
| Eject OK - warm restart
EJECT_WARM_RESTART:
        BRA     E_SoftReset                     | Warm restart to try again

| ----------------------------------------------------------
|
| DSAT_NOT_FOUND - DSAT not found - continue boot without alert table
|
DSAT_NOT_FOUND:
        MOVEQ.L #0x0,D7                         | D7 = 0 (no DSAT resource found)
        BRA     INIT_FONTS_BUFS                 | Continue boot without alert table

| ----------------------------------------------------------
|
| CHECK_BOOT_ERROR - Conditional system error - show error if D7 is nonzero
|
| Called during boot.
CHECK_BOOT_ERROR:
        TST.B   D7                              | Error flag set?
        BEQ.B   NO_BOOT_ERROR                   | No error: return
        _SysError                               | Show system error dialog
| Return (no error)
NO_BOOT_ERROR:
        RTS                                     | Return from CHECK_BOOT_ERROR

| ----------------------------------------------------------
|
| PATCH_LOAD_FAILED - Boot block patch load failed - restore BufPtr and continue
|
| Called during boot.
PATCH_LOAD_FAILED:
        ADDI.L  #0x400,(BufPtr).w               | Undo 1K tag buffer reservation

        BRA     OPEN_SYSTEM_RSRC                | Continue to System file open

| ----------------------------------------------------------
|
| CHECK_FILE_EXISTS - File existence check - call _GetFileInfo on file named by A3
|
| Called during boot.
CHECK_FILE_EXISTS:
        LEA.L   -0x400(A6),A0                   | A0 = param block on stack
        CLR     0x16(A0)                        | Default volume
        CLR.L   0x1A(A0)                        | ioFVersNum = 0, ioFDirIndex = 0
        MOVE.L  A3,0x12(A0)                     | ioFileName = file name to check
        _GetFileInfo                            | Check if file exists on disk
        RTS                                     | Return Z flag from _GetFileInfo

| ----------------------------------------------------------
|
| OPEN_BOOT_PATCH - Open and read file (D3=0: from BufPtr) - entry for boot patch loading
|
| Called during boot.
OPEN_BOOT_PATCH:
        MOVEQ.L #0x0,D3                         | D3 = 0: allocate from BufPtr
| Open file, read contents (D3 = alloc mode)
OPEN_AND_READ_FILE:
        LEA.L   -0x400(A6),A0                   | A0 = IOParam block on stack
        MOVEQ.L #-0x1,D2                        | D2 = -1 (error sentinel)
        LEA.L   0x12(A0),A2                     | A2 -> ioFileName field
        MOVE.L  A1,(A2)+                        | Set file name
        CLR.L   (A2)+                           | Clear ioVRefNum + ioFileType
        CLR.B   (A2)+                           | Clear ioVersNum
        MOVE.B  #0x1,(A2)+                      | ioPermssn = fsRdPerm (read only)
        PEA.L   0x400(A6)                       | ioMisc = buffer for driver
        MOVE.L  (SP)+,(A2)                      | Store ioMisc field
        _Open                                   | Open the file
        BNE.B   FILE_LOAD_RETURN                | Open failed: return error
        _GetEOF                                 | Get file size (EOF)
        BNE.B   CLOSE_FILE                      | GetEOF failed: close and return
        MOVE.L  (A2)+,D4                        | D4 = file size
        MOVEQ.L #0x2,D6                         | D6 = 2
        ASL     #0x8,D6                         | D6 = 0x200 = 512 (header size)
        SUB.L   D6,D4                           | D4 = file size - 512 (skip header)
        TST     D3                              | Check allocation mode (D3)
        BMI.B   ALLOC_FILE_BUFFER               | D3 < 0: allocate with _NewPtr
        BNE.B   LOAD_TO_BOOTBUF                 | D3 > 0: use boot block buffer
        MOVE.L  (BufPtr).w,A1                   | A1 = current BufPtr
        SUBA.L  D4,A1                           | Reserve D4 bytes from top
| Set up IOParam and read file data
SETUP_READ_PARAMS:
        LEA.L   -0x400(A6),A0                   | A0 = IOParam block
        LEA.L   0x20(A0),A2                     | A2 -> ioBuffer field
        MOVE.L  A1,(A2)+                        | ioBuffer = read destination
        MOVE.L  D4,(A2)+                        | ioReqCount = bytes to read
        ADDQ.W  #0x4,A2                         | Skip ioActCount
        MOVE    #0x1,(A2)+                      | ioPosMode = fsFromStart
        MOVE.L  D6,(A2)                         | ioPosOffset = skip header
        _Read                                   | Read file data into buffer
        BNE.B   CLOSE_FILE                      | Read error: close and return
        MOVEQ.L #0x0,D2                         | D2 = 0 (success)
| Close file (after read or error)
CLOSE_FILE:
        LEA.L   -0x400(A6),A0                   | A0 = IOParam block
        _Close                                  | Close the file
| Return result code from file load
FILE_LOAD_RETURN:
        MOVE    D2,D0                           | D0 = result code
        RTS                                     | Return from OPEN_BOOT_PATCH/OPEN_AND_READ_FILE

| ----------------------------------------------------------
|
| LOAD_TO_BOOTBUF - D3 > 0: load into boot block buffer area (+$800)
|
LOAD_TO_BOOTBUF:
        LEA.L   0x800(A6),A1                    | A1 = boot block buffer area
        ADD.L   D6,D4                           | Include header in count
        MOVEQ.L #0x0,D6                         | D6 = 0: read from offset 0
        BRA.B   SETUP_READ_PARAMS               | Go to read loop

| ----------------------------------------------------------
|
| ALLOC_FILE_BUFFER - D3 < 0: allocate buffer with _NewPtr for file contents
|
| Called during boot.
ALLOC_FILE_BUFFER:
        MOVE.L  D4,D0                           | D0 = size to allocate
        _NewPtr                                 | Allocate buffer
        MOVE    D0,D2                           | D2 = error from _NewPtr
        BNE.B   CLOSE_FILE                      | Alloc failed: close and return
        MOVE.L  A0,A1                           | A1 = allocated buffer
        BRA.B   SETUP_READ_PARAMS               | Go to read loop

| ----------------------------------------------------------
|
| SET_BLESSED_VOLUME - Set default volume to blessed folder using HFS _OpenWD + _SetVol
|
| Called during boot.
SET_BLESSED_VOLUME:
        TST.L   D0                              | D0 = blessed folder ID
        BEQ.B   SET_BLESSED_DONE                | Zero: no blessed folder, skip
        LEA.L   -0x400(A6),A0                   | A0 = param block
        CMPI.L  #0x2,D0                         | Root directory?
        BEQ.B   SET_BLESSED_DONE                | Yes: don't set WD
        MOVE.L  D0,0x30(A0)                     | ioWDDirID = blessed folder ID
        CLR.L   0x12(A0)                        | No file name (use dirID)
        MOVE.L  #0x4552494B,0x1C(A0)            | ioWDProcID = 'ERIK' (Finder signature)

        MOVEQ.L #0x1,D0                         | HFS dispatch selector 1 = OpenWD
        _HFSDispatch                            | Open working directory
        BNE.B   SET_BLESSED_DONE                | Failed: skip SetVol
        _SetVol                                 | Set as default volume
| Return from SET_BLESSED_VOLUME
SET_BLESSED_DONE:
        RTS                                     | Return from SET_BLESSED_VOLUME

| ----------------------------------------------------------
|
| INITFS_ALLOC_FAIL - _InitFS allocation failed - return -1
|
INITFS_ALLOC_FAIL:
        MOVEQ.L #-0x1,D0                        | Return -1 (init failed)
        RTS                                     | Return from INITFS_ALLOC_FAIL

| ----------------------------------------------------------
|
| _InitFS ($A06C)
|
| Called during boot.
InitFS:
        TST     (FSFCBLen).w                    | Already initialized? (>=0 = yes)
        BPL     INITFS_DONE                     | Yes: return noErr
        MOVE    #0x5E,(FSFCBLen).w              | FCB size = 94 bytes (HFS)
        LEA.L   (CkdDB).w,A0                    | A0 -> checked disk block table
        MOVEQ.L #0x50,D1                        | D1 = 80 (81 words to clear)
| Clear checked disk block table
CLEAR_CKDDB_LOOP:
        CLR     (A0)+                           | Zero the table entry
        DBF     D1,CLEAR_CKDDB_LOOP             | Loop for all entries
        MOVE    #0x2,(DrMstrBlk).w              | Master directory block = sector 2
        CMPI    #0x2,(MemTop).w                 | More than 128K RAM?
        BLE.B   FCB_COUNT_READY                 | No: use D0 as-is
        LSL     #0x2,D0                         | Yes: multiply FCB count by 4
| FCB count ready - allocate arrays
FCB_COUNT_READY:
        MOVE    D0,D2                           | D2 = number of FCBs
        MULU    #0x5E,D0                        | D0 = FCBs * 94 bytes each
        ADDQ.W  #0x2,D0                         | +2 for length word at start
        MOVE    D0,D1                           | D1 = total FCB array size
        _NewPtrSysClear                         | Allocate FCB array in system heap
        BNE.B   INITFS_ALLOC_FAIL               | Failed: return -1
        MOVE    D1,(A0)                         | Store length at start of array
        MOVE.L  A0,(FCBSPtr).w                  | FCBSPtr = FCB array base
        MULU    #0x10,D2                        | D2 = WDCBs * 16 bytes each
        MOVE.L  D2,D0                           | D0 = WDCB size
        ADDQ.W  #0x2,D0                         | +2 for length word
        MOVE    D0,D1                           | D1 = total WDCB size
        _NewPtrSysClear                         | Allocate WDCB array
        BNE.B   INITFS_ALLOC_FAIL               | Failed: return -1
        MOVE    D1,(A0)                         | Store length
        MOVE.L  A0,(WDCBsPtr).w                 | WDCBsPtr = WDCB array base
        MOVE.L  (SwitcherTPtr).w,A2             | A2 = switcher parameter table
        MOVE    A0,0x14(A2)                     | Store FCB ptr in switcher table
        MOVE    D1,0x16(A2)                     | Store WDCB size in switcher table
        MOVE.L  #0x510,D0                       | 0x510 bytes for HFS stack
        _NewPtrSysClear                         | Allocate HFS stack
        BNE.B   INITFS_ALLOC_FAIL               | Failed: return -1
        ADDA    #0x500,A0                       | Point to top of usable stack
        MOVE.L  A0,(HFSVars_HFSStkTop).w        | HFSStkTop = HFS stack top
        MOVEQ.L #0x38,D0                        | 56 bytes for PMSP buffer
        _NewPtrSysClear                         | Allocate PMSP
        BNE.B   INITFS_ALLOC_FAIL               | Failed: return -1
        MOVE    A0,0x18(A2)                     | Store in switcher table
        ADDQ.L  #0x6,A0                         | Skip 6-byte PMSP header
        MOVEQ.L #0x32,D0                        | PMSP size = 50
        MOVE    D0,(A0)                         | Store size in header
        MOVE.L  A0,(PMSPPtr).w                  | PMSPPtr = PMSP buffer
        MOVE    #0x200,D1                       | Block size = 512 bytes
        MOVEQ.L #0x1,D0                         | 1 block for bitmap cache
        JSR     InitCache(PC)                   | Initialize bitmap cache
        BNE     INITFS_ALLOC_FAIL               | Failed: return -1
        MOVE.L  A1,(SysBMCPtr).w                | SysBMCPtr = bitmap cache
        MOVEQ.L #0x1,D0                         | 1 block for volume cache (128K)
        CMPI    #0x2,(MemTop).w                 | More than 128K?
        BLE.B   ALLOC_VOL_CACHE                 | No: 1 block
        MOVEQ.L #0x2,D0                         | Yes: 2 blocks
| Allocate volume cache
ALLOC_VOL_CACHE:
        JSR     InitCache(PC)                   | Initialize volume cache
        BNE     INITFS_ALLOC_FAIL               | Failed: return -1
        MOVE.L  A1,(SysVolCPtr).w               | SysVolCPtr = volume cache
        MOVEQ.L #0x4,D0                         | 4 blocks for catalog cache (128K)
        CMPI    #0x2,(MemTop).w                 | More than 128K?
        BLE.B   ALLOC_CAT_CACHE                 | No: 4 blocks
        MOVEQ.L #0x10,D0                        | Yes: 16 blocks
| Allocate catalog cache
ALLOC_CAT_CACHE:
        JSR     InitCache(PC)                   | Initialize catalog cache
        BNE     INITFS_ALLOC_FAIL               | Failed: return -1
        MOVE.L  A1,(SysCtlCPtr).w               | SysCtlCPtr = catalog cache
        LEA.L   DSHook(PC),A0                   | Install disk-switch hook
        MOVE.L  A0,(DskSwtchHook).w             | DskSwtchHook -> DSHook
| InitFS complete - return noErr
INITFS_DONE:
        MOVEQ.L #0x0,D0                         | Return noErr
        RTS                                     | Return from InitFS

| ----------------------------------------------------------
|
| _InitEvents ($A06D)
|
| Called during boot.
InitEvents:
        MOVE    D0,D2                           | D2 = event count
        MOVEQ.L #0x16,D0                        | 22 bytes per event queue element
        MULU    D2,D0                           | D0 = total buffer size
        MOVE.L  D0,D1                           | D1 = save size for fill loop
        _NewPtrSysClear                         | Allocate event buffer
        LEA.L   (EvtBufCnt).w,A1                | A1 -> EvtBufCnt (end of queue header)
        SUBQ.W  #0x1,D2                         | D2 = max events - 1
        MOVE    D2,(A1)                         | EvtBufCnt = max - 1
        CLR.L   -(A1)                           | EvtQTail = nil
        CLR.L   -(A1)                           | EvtQHead = nil
        CLR     -(A1)                           | EvtQFlags = 0
        MOVE.L  A0,-(A1)                        | EvtBufPtr = allocated buffer
| Fill event buffer with 0xFFFF (free markers)
FILL_EVTBUF_LOOP:
        NOT     (A0)+                           | Mark event entry as free (0xFFFF)
        SUBQ.W  #0x2,D1                         | Decrement byte counter
        BNE.B   FILL_EVTBUF_LOOP                | Loop until buffer filled
        MOVE    #-0x11,-(A1)                    | SysEvtMask = 0xFFEF (all except keyUp)
        CLR     (KeyLast).w                     | Clear last key pressed
        RTS                                     | Return from InitEvents

