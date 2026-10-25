| Startup: hardware and manager initialization (StartInit)
|
| Apple source: StartInit.a (System 7.1: OS/StartMgr/StartInit.a). Reset
| entry (Boot_Startup_Hardware_Init, STARTINIT1, BOOTRETRY) and the
| initialization chain: JMPTBLINIT, memory and stack setup
| (FILLWITHONES, COMPBOOTSTACK, SETUPSYSAPPZONE), DRAWBEEPSCREEN, ADB and
| low-memory globals (INITADBVARS, INITHIMEMGLOBALS, INITGLOBALVARS), the
| Switcher table, GETPRAM, the interrupt vector tables (INITXVECTTABLES),
| WHICHCPU, SETUPTIMEK (timing constants), the SCSI, IWM, VIA and SCC
| chips (INITSCSI, INITIWM, INITVIA, INITSCC), video and cursor globals,
| GNEFILTER, and the manager initializations listed in MacSEROM.lst as
| modules: INITCRSRVARS, INITCRSRMGR, INITDISPATCHER (build the trap
| dispatch tables from os/dispatch_table.s), INITIOMGR, INITMEMMGR,
| INITRSRCMGR, INITTIMERMGR. The boot proper follows in boot_load.s.
|
| References: Inside Macintosh Vol III, Ch 2 and Vol IV/V (the startup
| sequence); Mac Plus tree: boot/vectors.s and boot/boot_install.s.

| Boot_Startup_Hardware_Init - first code executed after 68000 reset
| On SE FDHD, the reset vector at $0004 points here (ROM + $40).
| State at entry: SR = 0x2700 (supervisor, IPL=7), ROM overlay active.
| Sequence: disable interrupts -> RAM test -> hardware init -> boot.
Boot_Startup_Hardware_Init:
    MOVE.W	#0x2700,SR                           | supervisor mode, IPL=7 (mask all interrupts)
    JMP	STARTTEST1(PC)                          | jump to cold/warm start RAM test
| ----------------------------------------------------------
| STARTINIT1 - hardware initialization after initial RAM test passes
| STARTTEST1 returns here with A6 = top of RAM.
| D7 = CPU type from WHICHCPU (0=68000, 1=68010, 2=68020).
STARTINIT1:
    BSR.W	INITVIA                               | init VIA (6522): port dirs, RTC, sound
    BSR.W	INITSCC                               | init SCC (Z8530): reset both channels
    BSR.W	INITIWM                               | init IWM/SWIM disk controller
    BSR.W	INITSCSI                              | init SCSI controller (NCR 5380)
    BSR.W	WHICHCPU                              | detect CPU type -> D7
    MOVEA.L	A6,A1                               | A1 = MemTop (end of RAM)
    MOVEA.L	A6,A0                               | A0 = MemTop
    SUBA.W	#0x5900,A0                           | A0 = MemTop - 22784 (test range bottom)
    JSR	RAMTEST(PC)                             | test RAM from A0 to A1
    MOVEQ.L	#0x28,D0                            | D0 = 40 ticks beep duration (~0.67s)
    BSR.W	BOOTBEEP                              | sound the startup chime
    MOVEA.L	A7,A0                               | A0 = current SP (save for comparison)
    MOVEA.L	#0x40000,A1                         | A1 = 256K boundary
    CMPA.L	A1,A6                                | is MemTop >= 256K?
    BCC.B	WARMSTART_CHECK                       | yes: use 256K as stack limit
    MOVEA.L	A6,A1                               | no: cap stack at MemTop
| ----------------------------------------------------------
| WARMSTART_CHECK - check for warm-start signature before RAM test
| If WarmStart == 'WLSC' ($574C5343), the machine was warm-restarted
| and RAM contents are presumed good; skip the destructive RAM test.
WARMSTART_CHECK:
    CMPI.L	#0x574C5343,(WarmStart).W            | warm-start magic 'WLSC'?
    BEQ.B	SET_BOOT_STACK                        | yes: skip RAM test
    JSR	RAMTEST(PC)                             | no: test RAM from A0 (SP) to A1
| ----------------------------------------------------------
| SET_BOOT_STACK - set up initial stack pointer and fill low memory
| A1 = stack top (min of 256K, MemTop).
| Saves WarmStart across the low-memory fill so it survives the wipe.
SET_BOOT_STACK:
    MOVEA.L	A1,A7                               | set SP at top of tested RAM
    MOVE.L	(WarmStart).W,-(A7)                  | save WarmStart signature on stack
    LEA.L	(MonkeyLives).W,A0                    | A0 = start of low-mem fill (MonkeyLives)
    LEA.L	(0x1600).W,A1                         | A1 = end of low-mem fill
    BSR.W	FILLWITHONES                          | fill low memory with 0xFF
    MOVE.L	(A7)+,(WarmStart).W                  | restore WarmStart signature
    MOVE.B	D7,(CPUFlag).W                       | store CPU type (0/1/2) in CPUFlag
    MOVE.L	A6,(MemTop).W                        | store top of physical RAM
    LEA.L	POST_DEBUGGER_INIT(PC),A6             | A6 = return addr after debugger init
    JMP	SYSERRINIT(PC)                          | init SysError handler, install vectors
| ----------------------------------------------------------
| POST_DEBUGGER_INIT - continue boot after debugger/SysError vectors installed
| Calibrates timing loops, checks for external test software, then
| initializes all system managers in sequence.
POST_DEBUGGER_INIT:
    BSR.W	SETUPTIMEK                            | calibrate TimeDBRA/TimeSCCDB loop counts
    BSR.W	VIATIMERENABLES                       | enable VIA timer interrupts
    MOVEM.L	(0xF80080).L,D0/A0                  | load test software magic + entry from NuBus
    CMPI.L	#0x55AAAA55,D0                       | test software signature present?
    BNE.B	INIT_MANAGERS                         | no: continue normal boot
    LEA.L	BOOTRETRY(PC),A1                      | A1 = return addr after test software
    JMP	(A0)                                    | jump to external test software
| ----------------------------------------------------------
| INIT_MANAGERS - initialize high-memory globals, then all system managers
INIT_MANAGERS:
    BSR.W	INITHIMEMGLOBALS                      | set up sound buffers, BufPtr
BOOTRETRY:
    MOVE.W	#0x2700,SR                           | re-mask all interrupts for init
    BSR.W	INITGLOBALVARS                        | init low-mem globals (ROMBase, OneOne, etc.)
    BSR.W	INITXVECTTABLES                       | install interrupt dispatch vectors
    BSR.W	INITDISPATCHER                        | build A-line trap dispatch table
    BSR.W	GETPRAM                               | read PRAM: key repeat, caret, double-click
    BSR.W	INITMEMMGR                            | init Memory Manager (heap zones)
    BSR.W	SETUPSYSAPPZONE                       | create system + application heap zones
    BSR.W	INITSWITCHERTABLE                     | init Switcher/MultiFinder context table
    BSR.W	INITRSRCMGR                           | init Resource Manager (ROM resource map)
    BSR.W	INITTIMERMGR                          | init Time Manager (VIA Timer 2)
    BSR.W	INITADBVARS                           | init Apple Desktop Bus manager
    MOVE.W	#0x2000,SR                           | drop to IPL=0 (enable all interrupts)
    JSR	INITADB(PC)                             | init keyboard manager (ADB keyboard)
    BSR.W	INITVIDGLOBALS                        | init video globals (screen dimensions)
| Full RAM test (skipped on warm restart)
    MOVEA.L	A7,A0                               | A0 = current SP
    MOVEA.L	(BufPtr).W,A1                       | A1 = BufPtr (top of usable RAM)
    MOVEA.L	(MemTop).W,A6                       | A6 = physical top of RAM
    CMPI.L	#0x574C5343,(WarmStart).W            | warm-start signature present?
    BEQ.B	SETUP_BOOT_ENV                        | yes: skip destructive RAM test
    JSR	RAMTEST(PC)                             | no: test all RAM from SP to MemTop
| ----------------------------------------------------------
| SETUP_BOOT_ENV - set up boot environment: stack, drive queue, I/O
SETUP_BOOT_ENV:
    BSR.W	COMPBOOTSTACK                         | A0 = computed boot stack (MemTop/2 - 1K)
    MOVEA.L	A0,A7                               | set SP to boot stack position
    SUBA.W	#0x2000,A0                           | A0 = stack - 8K (application limit)
    _SetApplLimit                               | set application heap limit
    LEA.L	(DrvQHdr_Flags).W,A1                  | A1 = drive queue header
    JSR	INITQUEUE(PC)                           | init drive queue (empty)
    JSR	(0x41A19C).L                            | init File Manager (within ROM)
    BSR.W	INITIOMGR                             | init I/O Manager (Unit Table, drivers)
    BSR.W	INITCRSRMGR                           | init Cursor Manager
    MOVEA.L	(SysZone).W,A0                      | A0 = system zone base
    MOVEA.L	(A0),A0                             | A0 = system zone limit (bkLim)
    ADDA.W	#0x4000,A0                           | A0 += 16K (reserve above SysZone)
    _SetApplBase                                | set application zone base
    MOVE.L	(SysZone).W,(TheZone).W              | switch to system zone for allocs
    LEA.L	0x400(A7),A6                          | A6 = SP + 1K (GrafPort workspace)
    LEA.L	0x190(A7),A5                          | A5 = SP + 400 (QD globals workspace)
    BSR.W	DRAWBEEPSCREEN                        | draw rounded-rect startup screen
    MOVE.L	#0x574C5343,(WarmStart).W            | set warm-start signature 'WLSC'
    BRA.W	BOOTME                                | continue boot: load System, launch Finder
| ----------------------------------------------------------
| JMPTBLINIT - convert ROM-relative offset table to absolute addresses
| A0 = source table (word offsets relative to table start)
| A1 = destination (longword addresses to fill)
| D1 = number of entries - 1
JMPTBLINIT:
    MOVE.L	A0,D0                                | D0 = table base address
JMPTBL2:
    MOVEQ.L	#0x0,D2                             | clear D2 high word
    MOVE.W	(A0)+,D2                             | D2 = word offset from table base
    ADD.L	D0,D2                                 | D2 = absolute address (base + offset)
    MOVE.L	D2,(A1)+                             | store absolute address in dest table
    DBF.W	D1,JMPTBL2                            | loop for all entries
    RTS                                         | return from JMPTBLINIT
| ----------------------------------------------------------
| FILLWITHONES - fill memory range [A0..A1) with 0xFFFFFFFF
| A0 = start address, A1 = end address
| Used during boot to clear low memory before globals are set up.
FILLWITHONES:
    MOVE.L	A1,D0                                | D0 = end address
    SUB.L	A0,D0                                 | D0 = byte count (end - start)
    LSR.L	#0x2,D0                               | D0 = longword count
    MOVEQ.L	#-0x1,D1                            | D1 = 0xFFFFFFFF (fill pattern)
FILL_LOOP:
    MOVE.L	D1,(A0)+                             | write 0xFFFFFFFF, advance
    SUBQ.L	#0x1,D0                              | decrement counter
    BNE.B	FILL_LOOP                             | loop until all longwords filled
    RTS                                         | return from FILLWITHONES
| ----------------------------------------------------------
| COMPBOOTSTACK - compute boot stack position = MemTop/2 - 1K
| Returns A0 = boot stack address. Places stack at midpoint of RAM
| minus a 1K safety margin.
COMPBOOTSTACK:
    MOVE.L	(MemTop).W,D0                        | D0 = top of physical RAM
    LSR.L	#0x1,D0                               | D0 = MemTop / 2
    MOVEA.L	D0,A0                               | A0 = midpoint of RAM
    SUBA.W	#0x400,A0                            | A0 -= 1K safety margin
    RTS                                         | return from COMPBOOTSTACK
| ----------------------------------------------------------
| SETUPSYSAPPZONE - create system and application heap zones
| Uses DTAB_INITZONE parameter block to call _InitZone.
| Sets SysZone, RAMBase, ApplZone, HeapEnd, ApplLimit.
SETUPSYSAPPZONE:
    LEA.L	DTAB_INITZONE(PC),A0                  | A0 = InitZone parameter block
    _InitZone                                   | create system heap zone
    MOVE.L	(TheZone).W,(SysZone).W              | SysZone = newly created zone
    MOVE.L	(SysZone).W,(RAMBase).W              | RAMBase = system zone base
    MOVEA.L	(SysZone).W,A0                      | A0 = system zone
    MOVE.L	A0,(ApplZone).W                      | ApplZone = SysZone (initial)
    MOVEA.L	(A0),A0                             | A0 = zone limit (bkLim)
    MOVE.L	A0,(HeapEnd).W                       | HeapEnd = zone limit
    BSR.B	COMPBOOTSTACK                         | A0 = computed boot stack
    CMPA.L	A7,A0                                | is boot stack below current SP?
    BLS.B	SET_APPL_LIMIT                        | yes: use current SP
    MOVEA.L	A7,A0                               | no: cap at current SP
SET_APPL_LIMIT:
    SUBA.W	#0x2000,A0                           | A0 -= 8K (leave room for stack)
    _SetApplLimit                               | set application heap limit
    RTS                                         | return from SETUPSYSAPPZONE
| DTAB_INITZONE - InitZone parameter block (14 bytes)
| startPtr=$1600, limitPtr=$2E00, cGrowZone=$400000, cMoreMasters=0
DTAB_INITZONE:
    .long	0x00001600                            | startPtr: system zone starts at $1600
    .long	0x00002E00                            | limitPtr: initial zone limit at $2E00
    .long	0x00400000                            | cGrowZone: grow zone = 4MB
    .short	0x0000                               | cMoreMasters: 0 additional master ptrs
| ----------------------------------------------------------
| DRAWBEEPSCREEN - draw the startup rounded-rectangle screen
| Uses QuickDraw to draw a 3-pixel rounded-rect border inset from
| the screen edge, with a filled rounded-rect pattern inside.
| A5 = QD globals workspace, A6 = GrafPort workspace (SP + 1K).
DRAWBEEPSCREEN:
    PEA.L	-0x4(A5)                              | push @thePort (QD globals ptr)
    _InitGraf                                   | initialize QuickDraw
    PEA.L	-0x200(A6)                            | push GrafPort storage (512 bytes)
    _OpenPort                                   | open a GrafPort for drawing
    MOVEA.L	(A5),A2                             | A2 = QD globals base
    PEA.L	-0x6C(A2)                             | push arrow cursor data
    _SetCursor                                  | set cursor to arrow
    LEA.L	-0x74(A2),A0                          | A0 = screen bounds rect
    MOVE.L	A0,-(A7)                             | push rect ptr (for InsetRect)
    LEA.L	(scratch8).W,A1                       | A1 = scratch area for rect copy
    MOVE.L	A1,-(A7)                             | push scratch rect (for FrameRoundRect)
    MOVE.L	A1,-(A7)                             | push scratch rect (for InsetRect)
    MOVE.L	(A0)+,(A1)+                          | copy screen rect top-left to scratch
    MOVE.L	(A0),(A1)                            | copy screen rect bot-right to scratch
    MOVE.L	#0xFFFDFFFD,-(A7)                    | push inset (-3, -3) = expand 3 pixels
    _InsetRect                                  | inset scratch rect by -3 (expand)
    MOVE.L	#0x30003,-(A7)                       | push pen size (3, 3)
    _PenSize                                    | set pen to 3x3 pixels
    MOVE.L	#0x160016,-(A7)                      | push oval size (22, 22) for corners
    _FrameRoundRect                             | draw rounded-rect border
    _PenNormal                                  | reset pen to default (1, 1)
    MOVE.L	#0x100010,-(A7)                      | push oval size (16, 16) for fill
    PEA.L	-0x18(A2)                             | push gray pattern
    _FillRoundRect                              | fill inner rounded-rect with pattern
    RTS                                         | return from DRAWBEEPSCREEN
| ----------------------------------------------------------
| INITADBVARS - initialize Apple Desktop Bus manager variables
| Allocates 370 bytes ($172) for ADB data structures and installs
| the FDB shift-register interrupt handler into VIA level-1 dispatch.
INITADBVARS:
    MOVE.W	#0x172,D0                            | D0 = 370 bytes for ADB data block
    _NewPtrSysClear                             | allocate cleared ADB data in SysZone
    MOVE.L	A0,(ADBBase).W                       | store ADB data block pointer
    LEA.L	FDBSHIFTINT(PC),A0                    | A0 = ADB shift-register interrupt handler
    MOVE.L	A0,(Lvl1DT_2).W                      | install as VIA SR interrupt (slot 2)
    RTS                                         | return from INITADBVARS
| ----------------------------------------------------------
| INITHIMEMGLOBALS - set up high-memory globals (sound buffers, BufPtr)
| Allocates sound buffers just below MemTop, then sets BufPtr
| below the sound area. Memory layout (top down):
| MemTop -> [767 bytes PWM buffer] -> SoundBase -> [22K] -> BufPtr
INITHIMEMGLOBALS:
    MOVE.W	#0xFFFF,(PWMValue).W                 | PWMValue = max (sound off initially)
    MOVEA.L	(MemTop).W,A0                       | A0 = top of physical RAM
    SUBA.W	#0x2FF,A0                            | A0 -= 767 (PWM buffer size)
    MOVE.L	A0,(PWMBuf1).W                       | PWMBuf1 = sound buffer 1
    MOVE.L	A0,(PWMBuf2).W                       | PWMBuf2 = sound buffer 2 (same)
    SUBQ.W	#0x1,A0                              | A0 -= 1 (align to below buffer)
    MOVE.L	A0,(SoundBase).W                     | SoundBase = base of sound area
    SUBA.W	#0x5600,A0                           | A0 -= 22016 bytes (screen + reserve)
    MOVE.L	A0,(BufPtr).W                        | BufPtr = top of available heap
    RTS                                         | return from INITHIMEMGLOBALS
| ----------------------------------------------------------
| INITGLOBALVARS - initialize low-memory global variables
| Sets ROMBase, hardware flags, I/O vectors, initializes all
| hardware-specific globals, clears system state variables.
| HWCfgFlags $C400 = bit 15 (color QD), bit 14 (has FPU),
| bit 10 (ADB present) -- SE FDHD specific config.
INITGLOBALVARS:
    MOVE.L	#0x400000,(ROMBase).W                | ROM base address (always $400000)
    MOVE.B	#0x7F,(ROM85).W                      | ROM85 = $7F (positive = 128K+ ROM)
    MOVE.W	#0xC400,(HWCfgFlags).W               | HW config: ADB, no FPU, no color
    MOVE.L	#0x10001,(OneOne).W                  | OneOne = 1.0 in Fixed (hi=1, lo=1)
    MOVEQ.L	#-0x1,D0                            | D0 = 0xFFFFFFFF
    MOVE.L	D0,(MinusOne).W                      | MinusOne = -1 (constant)
    BSR.W	INITSCCGLOBALS                        | init SCC low-mem globals (SCCRd/SCCWr)
    BSR.W	INITIWMGLOBALS                        | init IWM/SWIM low-mem globals
    BSR.W	INITVIAGLOBALS                        | init VIA low-mem globals (VIA/VIA2)
    BSR.W	INITSCSIGLOBALS                       | init SCSI low-mem globals
    CLR.L	(DSAlertTab).W                        | no system error alert table yet
    MOVE.W	(MinusOne).W,(FSFCBLen).W            | FSFCBLen = -1 (MFS mode, not HFS)
    LEA.L	FSIODNETBL(PC),A0                     | A0 = I/O core vector table
    LEA.L	(JFetch).W,A1                         | A1 = JFetch/JStash/JIODone vectors
    MOVEQ.L	#0x2,D1                             | 3 vectors to install
    BSR.W	JMPTBLINIT                            | convert offsets to absolute addresses
    CLR.B	(DskVerify).W                         | disk verify off
    CLR.B	(LoadTrap).W                          | no custom trap loader
    CLR.B	(MmInOK).W                            | Memory Manager not ready yet
    CLR.W	(SysEvtMask).W                        | no system events enabled
    CLR.L	(JKybdTask).W                         | no keyboard task installed
    CLR.L	(StackLowPoint).W                     | no stack low-water mark
    LEA.L	(VBLQueueHdr_Flags).W,A1              | A1 = VBL queue header
    JSR	INITQUEUE(PC)                           | init VBL queue (empty)
    CLR.L	(Ticks).W                             | reset tick counter to 0
    MOVE.B	#0x80,(MBState).W                    | mouse button state = up (bit 7 set)
    CLR.L	(MBTicks).W                           | clear mouse-button tick counter
    CLR.L	(SysFontFam).W                        | system font family = 0 (Chicago)
    CLR.L	(WidthTabHandle).W                    | no font width table yet
    CLR.W	(TESysJust).W                         | TextEdit justification = left
    CLR.B	(WordRedraw).W                        | no word-level redraw
    JSR	INITCRSRVARS(PC)                        | init cursor variables
    CLR.W	(SysVersion).W                        | system version = 0 (not loaded yet)
    BCLR	#0x0,(AlarmState)                      | clear alarm armed bit
    LEA.L	GNEFILTER(PC),A0                      | A0 = ROM GNE filter routine
    MOVE.L	A0,(GNEFilter).W                     | install GNE filter (alarm check)
    CLR.L	(IAZNotify).W                         | no InitApplZone notification
    MOVE.W	#0xFF7F,(DiskVars_FlEvtMask).W       | floppy event mask: all except bit 7
    RTS                                         | return from INITGLOBALVARS
| ----------------------------------------------------------
| SWITCHGOODIES - Switcher/MultiFinder context table template (52 bytes)
| Copied to a heap block during INITSWITCHERTABLE. Contains
| default context-switch parameters: stack sizes, buffer sizes,
| and configuration words for the process manager.
SWITCHGOODIES:
    .long	0x04000400                            | default stack sizes (1K each)
    .long	0x0E000800                            | heap reserve / stack reserve
    .long	0x0B800080                            | switch buffer size / flags
    .long	0x03760002                            | context area size / count
    .long	0x03840002                            | param block size / count
    .long	0x03520004                            | resource map size / count
    .long	0x02F80002                            | file map size / count
    .long	0x03980004                            | event queue size / count
    .long	0x0D540004                            | VBL queue size / count
    .long	0x00000000                            | reserved
    .long	0x00000000                            | reserved
    .long	0x00000004                            | number of layers
    .long	0x00000000                            | reserved
| WDCBSWOS/PMSPSWOS - context switch parameter sizes
WDCBSWOS:
    .short	0x0024                               | WDCB switch-out size (36 bytes)
PMSPSWOS:
    .short	0x002A                               | PMSP switch-out size (42 bytes)
| ----------------------------------------------------------
| INITSWITCHERTABLE - allocate and init Switcher context table
| Copies 52-byte SWITCHGOODIES template to a system heap block
| and stores the pointer in SwitcherTPtr low-mem global.
INITSWITCHERTABLE:
    MOVEQ.L	#0x34,D0                            | D0 = 52 bytes for context table
    _NewPtrSysClear                             | allocate cleared block in SysZone
    MOVEA.L	A0,A1                               | A1 = allocated block (destination)
    LEA.L	SWITCHGOODIES(PC),A0                  | A0 = template data (source)
    MOVEQ.L	#0x34,D0                            | D0 = 52 bytes to copy
    _BlockMove                                  | copy template to heap block
    MOVE.L	A1,(SwitcherTPtr).W                  | store context table pointer
    RTS                                         | return from INITSWITCHERTABLE
| ----------------------------------------------------------
| GETPRAM - read PRAM settings for keyboard and mouse timing
| Reads SPKbd (key repeat speed) and SPClikCaret (double-click
| and caret blink rate) from PRAM, decodes packed nibble fields,
| and sets KeyRepThresh, KeyThresh, CaretTime, DoubleTime.
GETPRAM:
    _InitUtil                                   | init OS Utilities (reads PRAM)
    MOVEQ.L	#0x0,D1                             | clear D1
    MOVE.B	(SPKbd).W,D1                         | D1 = PRAM keyboard byte
    MOVEQ.L	#0xF,D0                             | D0 = low-nibble mask
    AND.W	D1,D0                                 | D0 = key repeat rate (lo nibble)
    BNE.B	PRAM_GOT_REPEAT                       | non-zero: use PRAM value
    MOVEQ.L	#0x48,D0                            | zero: default repeat = 72 ticks
PRAM_GOT_REPEAT:
    ADD.W	D0,D0                                 | double for threshold units
    MOVE.W	D0,(KeyRepThresh).W                  | set key repeat threshold
    LSR.W	#0x4,D1                               | D1 = key delay (hi nibble)
    BNE.B	PRAM_GOT_DELAY                        | non-zero: use PRAM value
    MOVE.W	#0x1FFF,D1                           | zero: default delay = very long
PRAM_GOT_DELAY:
    LSL.W	#0x2,D1                               | multiply by 4 for threshold units
    MOVE.W	D1,(KeyThresh).W                     | set key initial delay threshold
    MOVE.B	(SPClikCaret).W,D1                   | D1 = PRAM click/caret byte
    MOVEQ.L	#0xF,D0                             | D0 = low-nibble mask
    AND.B	D1,D0                                 | D0 = caret blink rate (lo nibble)
    LSL.B	#0x2,D0                               | multiply by 4 for tick count
    MOVE.L	D0,(CaretTime).W                     | set caret blink interval
    LSR.B	#0x2,D1                               | shift to get double-click field
    MOVEQ.L	#0x3C,D0                            | D0 = mask for bits 5-2
    AND.B	D1,D0                                 | D0 = double-click speed
    MOVE.L	D0,(DoubleTime).W                    | set double-click interval
    RTS                                         | return from GETPRAM
| ----------------------------------------------------------
| INITXVECTTABLES - install interrupt dispatch vector tables
| Sets up three vector tables in low memory:
| Lvl1DT[0..15] - VIA interrupt dispatch (16 slots)
|   slot 0 = ONESECINT (one-second timer)
|   slot 1 = VBLINT (vertical blanking)
|   all others = LVL2RTS (no-op return)
| Lvl2DT - SCC interrupt dispatch
|   slot 1 = EXTBINT (SCC channel B external/status)
|   slot 5 = EXTAINT (SCC channel A external/status)
| ExtStsDT[0..3] - external status dispatch (all = RTS)
| Lev1AutoVector - 68000 autovector table
|   level 1 = LVL1INT (VIA), level 2 = LVL2INT (SCC)
|   level 3 = SPURIOUS (unexpected interrupt)
INITXVECTTABLES:
    LEA.L	(Lvl1DT).W,A0                         | A0 = VIA interrupt dispatch table
    LEA.L	LVL2RTS(PC),A1                        | A1 = default handler (RTS)
    MOVEA.L	A0,A2                               | A2 = save table base for patching
    MOVEQ.L	#0xF,D0                             | 16 slots to fill
FILL_LVL1DT:
    MOVE.L	A1,(A0)+                             | fill slot with RTS handler
    DBF.W	D0,FILL_LVL1DT                        | loop for all 16 slots
    LEA.L	ONESECINT(PC),A0                      | A0 = one-second interrupt handler
    MOVE.L	A0,(A2)+                             | Lvl1DT[0] = ONESECINT
    LEA.L	VBLINT(PC),A0                         | A0 = VBL interrupt handler
    MOVE.L	A0,(A2)                              | Lvl1DT[1] = VBLINT
    LEA.L	(Lvl2DT_1).W,A2                       | A2 = SCC interrupt dispatch table
    LEA.L	EXTBINT(PC),A0                        | A0 = SCC channel B ext/status handler
    MOVE.L	A0,(A2)                              | Lvl2DT[1] = EXTBINT (ch B DCD/mouse)
    LEA.L	EXTAINT(PC),A0                        | A0 = SCC channel A ext/status handler
    MOVE.L	A0,0x10(A2)                          | Lvl2DT[5] = EXTAINT (ch A DCD)
    LEA.L	(ExtStsDT).W,A2                       | A2 = external status dispatch table
    LEA.L	LVL2RTS(PC),A0                        | A0 = default RTS handler
    MOVE.L	A0,(A2)+                             | ExtStsDT[0] = RTS
    MOVE.L	A0,(A2)+                             | ExtStsDT[1] = RTS
    MOVE.L	A0,(A2)+                             | ExtStsDT[2] = RTS
    MOVE.L	A0,(A2)                              | ExtStsDT[3] = RTS
    LEA.L	(Lev1AutoVector).W,A2                 | A2 = 68000 autovector table
    LEA.L	LVL1INT(PC),A0                        | A0 = level 1 (VIA) handler
    MOVE.L	A0,(A2)+                             | autovector 1 = LVL1INT
    LEA.L	LVL2INT(PC),A0                        | A0 = level 2 (SCC) handler
    MOVE.L	A0,(A2)+                             | autovector 2 = LVL2INT
    LEA.L	SPURIOUS(PC),A0                       | A0 = spurious interrupt handler
    MOVE.L	A0,(A2)                              | autovector 3 = SPURIOUS
    RTS                                         | return from INITXVECTTABLES
| ----------------------------------------------------------
| WHICHCPU - detect CPU type (68000 vs 68010 vs 68020+)
| Attempts to execute MOVEC D0,CACR (68020+ instruction).
| If it causes an illegal instruction exception: 68010 or 68000.
| Distinguishes 68010 from 68000 by checking the exception
| frame format word (68010 pushes format=$10, 68000 does not).
| Returns D7: 0=68000, 1=68010, 2=68020+.
WHICHCPU:
    LEA.L	(IllegalInstructionVector).W,A1       | A1 = illegal instruction vector
    MOVE.L	(A1),-(A7)                           | save current illegal-instr handler
    LEA.L	WHICHCPU_TRAP(PC),A0                  | A0 = our trap handler
    MOVE.L	A0,(A1)                              | install temporary trap handler
    MOVEA.L	A7,A0                               | A0 = save SP (for cleanup)
    CLR.W	-(A7)                                 | push dummy format word
    MOVEQ.L	#0x2,D1                             | D1 = 2 (assume 68020+)
    MOVEQ.L	#0x1,D0                             | D0 = 1 (enable instruction cache)
    .byte 0x4E,0x7B,0x00,0x02                   | MOVEC D0,CACR (68020+ only)
    BRA.B	WHICHCPU_DONE                         | success: CPU is 68020+, D1=2
| Illegal instruction trap handler: MOVEC caused exception
WHICHCPU_TRAP:
    MOVEQ.L	#0x1,D1                             | D1 = 1 (assume 68010)
    CMPI.W	#0x10,0x6(A7)                        | check exception frame format word
    BEQ.B	WHICHCPU_DONE                         | format=$10: yes, 68010
    MOVEQ.L	#0x0,D1                             | format=0: plain 68000
WHICHCPU_DONE:
    MOVEA.L	A0,A7                               | restore SP (discard exception frame)
    MOVE.L	(A7)+,(A1)                           | restore original illegal-instr handler
    MOVE.B	D1,D7                                | D7 = CPU type (0/1/2)
    RTS                                         | return from WHICHCPU
| ----------------------------------------------------------
| SETUPTIMEK - calibrate TimeDBRA and TimeSCCDB timing constants
| Measures how many DBF loop iterations fit in one VIA Timer 1
| interrupt period. Two measurements:
| 1. TimeDBRA: plain DBF loop (used by _Delay and driver timing)
| 2. TimeSCCDB: DBF loop with SCC read (used by SCC settling delays)
| Method: set Timer 1 to very short period, count DBF iterations
| until the timer fires, then NOT the count (DBF counts down from -1).
SETUPTIMEK:
    MOVE.W	SR,-(A7)                             | save SR (will modify IPL)
    MOVE.L	(Lev1AutoVector).W,-(A7)             | save level-1 autovector
    MOVEA.L	#0xEFE1FE,A1                        | A1 = VIA base (PortB)
    BCLR	#0x5,0x1600(A1)                        | T1 free-run mode (ACR bit 5 = 0)
    MOVE.B	#0xFF,0x1200(A1)                     | T1 counter-hi = 0xFF (short period)
    MOVE.B	#0xA0,0x1C00(A1)                     | IER = 0xA0: enable T1 interrupt
    ANDI.W	#0xF8FF,SR                           | drop IPL to 0 (enable interrupts)
    MOVE.L	A7,D1                                | D1 = save SP for cleanup
| --- Measure TimeDBRA (plain DBF loop) ---
    LEA.L	TIMEK_DBRA_DONE(PC),A0                | A0 = T1 interrupt handler
    MOVE.L	A0,(Lev1AutoVector).W                | install as level-1 handler
    MOVEQ.L	#-0x1,D0                            | D0 = -1 (DBF counts from 65535)
    BRA.B	TIMEK_DBRA_START                      | enter timing loop
TIMEK_DBRA_BODY:
    MOVE.B	#0xF,0x1000(A1)                      | T1 counter-lo latch = 15
    MOVE.B	#0x3,0x1200(A1)                      | T1 counter-hi = 3 (restart timer)
TIMEK_DBRA_LOOP:
    DBF.W	D0,TIMEK_DBRA_LOOP                    | count iterations until T1 fires
    BRA.B	TIMEK_DBRA_DONE                       | (overflow: should not reach here)
TIMEK_DBRA_START:
    BRA.B	TIMEK_DBRA_BODY                       | start first timer period
TIMEK_DBRA_DONE:
    TST.B	0x1000(A1)                            | clear VIA T1 interrupt flag
    NOT.W	D0                                    | D0 = ~D0 = iterations counted
    MOVE.W	D0,(TimeDBRA).W                      | store plain-loop calibration
    MOVEA.L	D1,A7                               | restore SP
| --- Measure TimeSCCDB (DBF loop with SCC read) ---
    ANDI.W	#0xF8FF,SR                           | drop IPL to 0 again
    LEA.L	TIMEK_SCC_DONE(PC),A0                 | A0 = T1 interrupt handler
    MOVE.L	A0,(Lev1AutoVector).W                | install as level-1 handler
    MOVEA.L	#0x9FFFF8,A0                        | A0 = SCC read base (for settling)
    MOVEQ.L	#-0x1,D0                            | D0 = -1 (DBF counts from 65535)
    BRA.B	TIMEK_SCC_START                       | enter SCC timing loop
TIMEK_SCC_BODY:
    MOVE.B	#0xF,0x1000(A1)                      | T1 counter-lo latch = 15
    MOVE.B	#0x3,0x1200(A1)                      | T1 counter-hi = 3 (restart timer)
TIMEK_SCC_LOOP:
    BTST	#0x0,(A0)                              | read SCC (adds bus settling time)
    DBF.W	D0,TIMEK_SCC_LOOP                     | count iterations until T1 fires
    BRA.B	TIMEK_SCC_DONE                        | (overflow)
TIMEK_SCC_START:
    BRA.B	TIMEK_SCC_BODY                        | start first timer period
TIMEK_SCC_DONE:
    TST.B	0x1000(A1)                            | clear VIA T1 interrupt flag
    NOT.W	D0                                    | D0 = iterations with SCC read
    MOVE.W	D0,(TimeSCCDB).W                     | store SCC-loop calibration
    MOVEA.L	D1,A7                               | restore SP
    MOVE.B	#0x20,0x1C00(A1)                     | IER = 0x20: disable T1 interrupt
    MOVE.L	(A7)+,(Lev1AutoVector).W             | restore original level-1 handler
    MOVE.W	(A7)+,SR                             | restore original SR (IPL)
    RTS                                         | return from SETUPTIMEK
| ----------------------------------------------------------
| INITSCSIGLOBALS - set SCSI controller base addresses in low memory
| NCR 5380 at $5FF000 (base), $5FF200 (DMA/handshake).
INITSCSIGLOBALS:
    MOVE.L	#0x5FF000,(SCSIBase).W               | SCSI base = NCR 5380 register base
    MOVE.L	#0x5FF200,(SCSIDMA).W                | SCSI DMA base = handshake registers
    MOVE.L	#0x5FF200,(SCSIHsk).W                | SCSI handshake = same as DMA
    RTS                                         | return from INITSCSIGLOBALS
| ----------------------------------------------------------
| INITSCSI - reset NCR 5380 SCSI controller
| Clears the four control registers (ICR, MR, TCR, SER)
| by writing 0 to offsets $10, $20, $30, $40 from base + 1.
INITSCSI:
    LEA.L	(0x5FF001).L,A0                       | A0 = SCSI odd-byte base
    CLR.B	0x10(A0)                              | clear ICR (Initiator Command Reg)
    CLR.B	0x20(A0)                              | clear MR (Mode Register)
    CLR.B	0x30(A0)                              | clear TCR (Target Command Reg)
    CLR.B	0x40(A0)                              | clear SER (Select Enable Reg)
    RTS                                         | return from INITSCSI
| ----------------------------------------------------------
| INITIWMGLOBALS - set the low-memory pointer IWM to the floppy disk
| controller (the IWM; the SWIM of the SE FDHD sits at the same place).
| It is on the low data byte (odd addresses); its address lines A0-A3 are
| CPU A9-A12, so its 16 addresses are $200 apart from $DFE1FF on.
INITIWMGLOBALS:
    MOVE.L	#0xDFE1FF,(IWM).W                    | IWM base = $DFE1FF
    RTS                                         | return from INITIWMGLOBALS
| ----------------------------------------------------------
| INITIWM - initialize the floppy disk controller (Apple's InitIWM): set
| the IWM mode register to $17 (IWMInitMode in Apple's
| HardwarePrivateEqu.a) = latch mode, asynchronous handshake, 1-second
| timer off, slow mode, 8 MHz (IWM Design Spec, "Mode register"; see
| SetIWMMode in the 1987 .Sony driver for why slow mode). The mode
| register can only be written while no drive enable is active (status
| bit 5 = 0; with the timer on that is up to a second after LMotor-On
| was cleared -- SWIM Chip User's Ref, "Set Mode"). The loop repeats
| until the status register echoes the mode; as the status is ANDed with
| $17 first, only bits 0-2 and 4 are checked (Apple's InitIWM does the
| same).
INITIWM:
    MOVEA.L	#0xDFE1FF,A0                        | A0 = IWM base address
    MOVEQ.L	#0x17,D0                            | D0 = desired mode register value
IWM_INIT_LOOP:
    TST.B	mtrOff(A0)                            | mtrOff: LMotor-On = 0, drive enable off
    TST.B	q6H(A0)                               | Q6H: L6 = 1, status register selected
    MOVE.B	q7L(A0),D2                           | Q7L (L7 = 0): read the status register
    BTST	#0x5,D2                                | status bit 5: a drive enable still active?
    BNE.B	IWM_INIT_LOOP                         | yes: wait until it is off
    AND.B	D0,D2                                 | keep the bits set in $17
    CMP.B	D0,D2                                 | all of them set (mode bits 0-4 = status 0-4)?
    BEQ.B	IWM_INIT_DONE                         | yes: skip write
    MOVE.B	D0,q7H(A0)                           | Q7H (L6 = 1, enable off): write the mode register
    TST.B	q7L(A0)                               | Q7L: L7 = 0, status register again
    BRA.B	IWM_INIT_LOOP                         | re-read to verify
IWM_INIT_DONE:
    TST.B	q6L(A0)                               | Q6L: L6 = 0, read mode
    RTS                                         | return from INITIWM
| ----------------------------------------------------------
| INITVIAGLOBALS - set VIA base address in low memory
INITVIAGLOBALS:
    MOVE.L	#0xEFE1FE,(VIA).W                    | VIA base = $EFE1FE (PortB)
    RTS                                         | return from INITVIAGLOBALS
| ----------------------------------------------------------
| INITVIA - initialize VIA 6522 peripheral interface
| Sets port A output (volume, overlay, drive select), port B
| direction (RTC, sound, mouse), clears pending interrupts.
INITVIA:
    MOVEA.L	#0xEFE1FE,A0                        | A0 = VIA base (PortB)
    MOVE.B	#0x69,0x1E00(A0)                     | PortA = $69: vol=1, overlay off, page2
    MOVE.B	#0x7F,0x600(A0)                      | DDRA = $7F: PA0-6 output, PA7 input
    MOVE.B	#0xC7,(A0)                           | PortB = $C7: RTC disable, sound off
    MOVE.B	#0xC7,0x400(A0)                      | DDRB = $C7: PB0-2,6-7 out, PB3-5 in
    MOVE.B	#0x7F,0x1C00(A0)                     | IER = $7F: disable all VIA interrupts
    RTS                                         | return from INITVIA
| ----------------------------------------------------------
| VIATIMERENABLES - enable VIA Timer 1 and Timer 2 interrupts
VIATIMERENABLES:
    MOVEA.L	#0xEFE1FE,A0                        | A0 = VIA base
    ANDI.B	#0xF0,0x1800(A0)                     | PCR low nibble = 0 (CB2 input)
    MOVE.B	#0x83,0x1C00(A0)                     | IER = $83: enable T1 + T2 interrupts
    RTS                                         | return from VIATIMERENABLES
| ----------------------------------------------------------
| INITSCCGLOBALS - set SCC base addresses and clear poll proc
INITSCCGLOBALS:
    MOVE.L	#0xBFFFF9,(SCCWr).W                  | SCC write control base
    MOVE.L	#0x9FFFF8,(SCCRd).W                  | SCC read control base
    CLR.L	(PollProc).W                          | no SCC poll procedure
    RTS                                         | return from INITSCCGLOBALS
| Boot-time I/O Manager Install (SCC reset, jump-table setup, driver install)
|
| Reached from vectors.s:InitIOMgr-caller during the boot sequence, after
| memory test and hardware setup but before the full OS is initialized.
|
| Contents:
| DT_SCC_INIT_DATA - SCC channel-init register table (17 bytes per channel)
| InitSCC - reset both SCC channels, stream register writes
| SCC_WRITE_REGS/LOOP- register write with settling delay
| JmpTblInit / L_mJmpTbl2 - expand ROM-relative offset table into absolute
| jump vectors (JFetch/JStash/JIODone)
| DT_SONY_NAME / DT_SOUND_NAME - Pascal-string driver names
| InitIOMgr - allocate 48-slot Unit Table, _Open .Sony + .Sound,
| issue SCSI reset (v1/v2 inline vs v3 patch jump),
| load and run the 'SERD' serial-driver resource.
|
| Mirrors the layout of src/original/boot/boot_install.s from the 128K/512K
| ROM (which holds the smaller, classic-era variant of the same routines).
|
| Called once during boot, never again.
| References: Inside Macintosh II, Ch 6 (Device Manager, driver install).

| DT_SCC_INIT_DATA - SCC initialization register data (17 bytes per channel)
| Written sequentially to SCC write control register to reset and
| configure each channel. Values are SCC register address/data pairs.
| DT_SCC_INIT_DATA - SCC initialization register data (32 bytes)
| Written sequentially to SCC write register to reset and configure
| each channel. Format: register-number/value pairs.
| Channel B first (reset $40), then channel A (reset $80).
DT_SCC_INIT_DATA:
    .byte 0x09,0x40,0x04,0x4C                   | WR9=$40 (reset ch B), WR4=$4C (x16, 1 stop)
    .byte 0x02,0x00,0x03,0xC0                   | WR2=$00 (int vector), WR3=$C0 (Rx 8-bit)
    .byte 0x0F,0x08,0x00,0x10                   | WR15=$08 (DCD IE), WR0=reset ext/status
    .byte 0x00,0x10,0x01,0x01                   | WR0=reset ext/status, WR1=$01 (ext int)
    .byte 0x09,0x80,0x04,0x4C                   | WR9=$80 (reset ch A), WR4=$4C (x16, 1 stop)
    .byte 0x03,0xC0,0x0F,0x08                   | WR3=$C0 (Rx 8-bit), WR15=$08 (DCD IE)
    .byte 0x00,0x10,0x00,0x10                   | WR0=reset ext x2
    .byte 0x01,0x01,0x09,0x0A                   | WR1=$01 (ext int), WR9=$0A (MIE+NV)
| ----------------------------------------------------------
| INITSCC - reset and configure the Zilog 8530 SCC
| Writes 17 register bytes to each channel (B then A) from
| DT_SCC_INIT_DATA. Configures: async mode, 8-bit data, 1 stop bit,
| external/status interrupts enabled (for mouse DCD tracking).
INITSCC:
    MOVEA.L	#0xBFFFF9,A0                        | A0 = SCC write channel B
    MOVEA.L	#0x9FFFF8,A1                        | A1 = SCC read channel B
    TST.B	-0x1(A1)                              | dummy read to reset SCC state
    LEA.L	DT_SCC_INIT_DATA(PC),A2               | A2 = SCC init register data
    MOVEQ.L	#0x10,D1                            | 17 bytes for channel B
    BSR.B	WRITESCC                              | write register data to channel B
    ADDQ.L	#0x2,A0                              | advance to channel A write
    ADDQ.L	#0x2,A1                              | advance to channel A read
    MOVEQ.L	#0x10,D1                            | 17 bytes for channel A
    BSR.B	WRITESCC                              | write register data to channel A
    RTS                                         | return from INITSCC
| ----------------------------------------------------------
| WRITESCC - write D1+1 bytes from (A2) to SCC register (A0)
| Includes delay loops (MOVE.L (SP),(SP)) for SCC register settling.
WRITESCC:
    MOVE.B	(A1),D2                              | dummy read to reset register pointer
    BRA.B	SCC_WRITE_ENTER                       | enter write loop
SCC_WRITE_LOOP:
    MOVE.L	(A7),(A7)                            | stall 1 (bus-settling no-op)
    MOVE.L	(A7),(A7)                            | stall 2 (SCC needs ~500ns idle)
    MOVE.B	(A2)+,(A0)                           | write next register byte to SCC
SCC_WRITE_ENTER:
    DBF.W	D1,SCC_WRITE_LOOP                     | loop for all register bytes
    RTS                                         | return from WRITESCC
| ----------------------------------------------------------
| INITVIDGLOBALS - initialize video/screen globals
| SE FDHD: 512x342 built-in display, 64 bytes/row, 60 Hz.
INITVIDGLOBALS:
    MOVE.L	(BufPtr).W,(ScrnBase).W              | screen base = top of heap buffer
    MOVE.W	#0x40,(ScreenRow).W                  | row bytes = 64 (512 pixels / 8)
    MOVE.W	#0x3C,(VertRRate).W                  | vertical refresh = 60 Hz
    MOVE.L	#0x480048,(ScrVRes).W                | screen resolution = 72x72 dpi
    RTS                                         | return from INITVIDGLOBALS
| ----------------------------------------------------------
| INITCRSRVARS - clear QuickDraw cursor globals
| Zeros the range from JHideCursor through WWExist-1.
INITCRSRVARS:
    LEA.L	(GrafBegin_JHideCursor).W,A0          | A0 = start of cursor globals
    LEA.L	(WWExist).W,A1                        | A1 = end of cursor globals
CLR_CRSRVARS_LOOP:
    CLR.W	(A0)+                                 | clear next word
    CMPA.L	A1,A0                                | reached end?
    BCS.B	CLR_CRSRVARS_LOOP                     | no: continue
    RTS                                         | return from INITCRSRVARS
| ----------------------------------------------------------
| INITCRSRMGR - initialize Cursor Manager
| Sets up mouse position, screen bounds, mickey-to-pixel table,
| and installs cursor J-vectors for QuickDraw.
INITCRSRMGR:
    MOVE.L	#0xF000F,D0                          | D0 = initial mouse pos (15,15)
    LEA.L	(MTemp_v).W,A0                        | A0 = mouse temp variables
    MOVE.L	D0,(A0)+                             | MTemp = (15,15)
    MOVE.L	D0,(A0)+                             | RawMouse = (15,15)
    MOVE.L	D0,(A0)+                             | Mouse = (15,15)
    CLR.L	(A0)+                                 | CrsrRect top-left = (0,0)
    MOVE.W	#0x156,(A0)+                         | CrsrRect bottom = 342
    MOVE.W	#0x200,(A0)                          | CrsrRect right = 512
    MOVEQ.L	#0x1C,D0                            | D0 = 28 bytes for mickey table
    _NewPtrSys                                  | allocate mickey-to-pixel table
    MOVE.L	A0,(MickeyBytes).W                   | store table pointer
    MOVE.W	#0x1,(A0)                            | acceleration threshold = 1
    MOVE.W	#0x8,0x2(A0)                         | acceleration factor = 8
    CLR.W	0x12(A0)                              | clear mouse scaling flag
    LEA.L	DTAB_MICKEY(PC),A1                    | A1 = default mickey table data
    ADDA.W	#0x14,A0                             | A0 = offset $14 in mickey block
    MOVE.L	(A1)+,(A0)+                          | copy mickey data word 1
    MOVE.L	(A1),(A0)                            | copy mickey data word 2
| Install cursor J-vectors (JHideCursor..JInitCrsr)
    LEA.L	(WWExist).W,A1                        | A1 = just past cursor seed area
    LEA.L	(0x418FB8).L,A0                       | A0 = ROM cursor routine base
    MOVE.L	A0,-(A1)                             | store cursor seed routine addr
    MOVE.W	#0x6,-(A1)                           | cursor seed = 6
    LEA.L	(0x418DBC).L,A0                       | A0 = cursor J-vector offset table
    LEA.L	(GrafBegin_JHideCursor).W,A1          | A1 = J-vector destination
    MOVEQ.L	#0x7,D1                             | 8 J-vectors to install
    BSR.W	JMPTBLINIT                            | convert offsets to absolute addrs
    MOVEQ.L	#-0x1,D0                            | D0 = 0xFFFF / 0xFFFFFFFF
    MOVE.W	D0,(CrsrNew).W                       | CrsrNew = true (cursor needs update)
    MOVE.L	D0,(MouseMask).W                     | MouseMask = all 1s (no masking)
    RTS                                         | return from INITCRSRMGR
| DTAB_MICKEY - default mouse acceleration table data (8 bytes)
DTAB_MICKEY:
    .short	0x040A                               | mickey threshold / multiplier
    .long	0x0FFFFF53                            | acceleration curve parameters
    .short	0x4D48                               | 'MH' signature
| ----------------------------------------------------------
| GNEFILTER - GetNextEvent filter (alarm menu flash + beep)
| Installed in GNEFilter low-mem vector. Called on every
| GetNextEvent. Checks if alarm is armed and ready to flash
| the Apple menu bar area. If so, XORs the Apple logo area
| to create a blinking effect and optionally beeps.
GNEFILTER:
    LEA.L	(AlarmState).W,A1                     | A1 = AlarmState low-memory address
    BSET	#0x5,(A1)                              | set 'GNE filter ran' bit
    BNE.B	GNE_FILTER_DONE                       | already set: skip alarm check
    MOVEQ.L	#0x3,D0                             | D0 = alarm mask (bits 0-1)
    AND.B	(A1),D0                               | check if alarm is armed/active
    BNE.B	GNE_FILTER_DONE                       | alarm not ready: skip
    TST.B	(WWExist).W                           | Window Manager initialized?
    BNE.B	GNE_FILTER_DONE                       | not yet: skip alarm display
    MOVE.L	(MenuList).W,D0                      | D0 = MenuList handle
    BEQ.B	GNE_FILTER_DONE                       | no menus: skip
    MOVEA.L	D0,A0                               | A0 = deref MenuList handle
    MOVEA.L	(A0),A0                             | A0 = deref again (master ptr)
    TST.W	(A0)                                  | any menus in menu bar?
    BLE.B	GNE_FILTER_DONE                       | no menus: skip
    MOVEA.L	0x6(A0),A0                          | A0 = first menu handle
    MOVEA.L	(A0),A0                             | A0 = deref menu handle
    CMPI.W	#0x114,0xE(A0)                       | Apple menu width = 276 pixels?
    BNE.B	GNE_FILTER_DONE                       | wrong width: skip flash
    MOVE.L	#0x10011,-(A7)                       | push shield rect top-left (1,17)
    MOVE.L	#0x13001E,-(A7)                      | push shield rect bot-right (19,30)
    MOVEA.L	(JShieldCursor).W,A0                | shield cursor from drawing
    JSR	(A0)                                    | call JShieldCursor
    MOVEA.L	(ScrnBase).W,A0                     | A0 = screen base
    MOVE.W	(ScreenRow).W,D0                     | D0 = bytes per scanline (64)
    MOVE.L	#0x7FFC,D1                           | XOR mask: flip bits 2-14
    MOVEQ.L	#0x11,D2                            | 18 scanlines (menu bar height)
ALARM_FLASH_LOOP:
    ADDA.W	D0,A0                                | advance to next scanline
    EOR.L	D1,(A0)                               | XOR Apple logo area
    DBF.W	D2,ALARM_FLASH_LOOP                   | loop 18 scanlines
    MOVEA.L	(JShowCursor).W,A0                  | restore cursor
    JSR	(A0)                                    | call JShowCursor
    BCHG	#0x7,(A1)                              | toggle alarm flash state
    BCLR	#0x6,(A1)                              | clear 'alarm triggered' bit
    BEQ.B	GNE_FILTER_DONE                       | not triggered: return quietly
    MOVE.W	#0x8,-(A7)                           | push duration = 8
    _SysBeep                                    | sound the alarm beep
| Called by: GNEFILTER, ALARM_FLASH_LOOP
GNE_FILTER_DONE:
    RTS                                         | return from GNEFILTER
| ----------------------------------------------------------
| INITDISPATCHER - build A-line trap dispatch tables
| Fills ToolTable (512 entries) and DispatchTab (256 entries)
| with P_tUnimplemented, then decodes the compressed dispatch
| table from ROM to populate actual trap handler addresses.
| The compressed format uses delta-encoded offsets:
| - 2-byte positive: 15-bit signed delta x2 from current ROM ptr
| - 1-byte negative ($80-$FE): 7-bit delta x2 (short form)
| - $FF escape: next 4 bytes are absolute ROM offset
| - $00 delta: end of Toolbox entries, switch to OS entries
INITDISPATCHER:
    LEA.L	(ToolTable).W,A0                      | A0 = Toolbox trap table (512 entries)
    LEA.L	P_tUnimplemented(PC),A1               | A1 = unimplemented trap handler
    MOVE.W	#0x1FF,D0                            | 512 Toolbox entries to fill
FILL_TOOL_DISP:
    MOVE.L	A1,(A0)+                             | fill with unimplemented handler
    DBF.W	D0,FILL_TOOL_DISP                     | loop for all 512 entries
    LEA.L	(DispatchTab).W,A0                    | A0 = OS trap table (256 entries)
    MOVE.W	#0xFF,D0                             | 256 OS entries to fill
FILL_OS_DISP:
    MOVE.L	A1,(A0)+                             | fill with unimplemented handler
    DBF.W	D0,FILL_OS_DISP                       | loop for all 256 entries
| Decode compressed dispatch table from ROM
    MOVEA.L	(ROMBase).W,A0                      | A0 = ROM base
    ADDA.L	DT_mDispOff(PC),A0                   | A0 = compressed table start
    LEA.L	(ToolTable).W,A1                      | A1 = destination: Toolbox table
    MOVEA.L	(ROMBase).W,A2                      | A2 = running ROM address
    MOVE.W	#0x200,D0                            | D0 = 512 entries (Toolbox first)
    MOVEQ.L	#0x7F,D2                            | D2 = mask for 7-bit field
DECODE_DISPATCH:
    MOVE.B	(A0)+,D1                             | read first byte of entry
    BMI.B	DECODE_SHORT                          | negative: short-form delta
    ASL.W	#0x8,D1                               | shift to high byte
    MOVE.B	(A0)+,D1                             | read low byte (15-bit value)
    ADD.W	D1,D1                                 | double to get word offset
    EXT.L	D1                                    | sign-extend to longword
    BEQ.B	DECODE_DONE                           | zero delta: end of section
DISP_ADD_DELTA:
    ADDA.L	D1,A2                                | A2 += delta (new ROM address)
    MOVE.L	A2,(A1)                              | store handler address in table
DECODE_NEXT:
    ADDQ.W	#0x4,A1                              | advance to next table entry
    SUBQ.W	#0x1,D0                              | decrement entry counter
    BNE.B	DECODE_DISPATCH                       | more entries: continue
    MOVEQ.L	#-0x1,D0                            | D0 = -1 (unlimited for OS table)
    LEA.L	(DispatchTab).W,A1                    | A1 = switch to OS trap table
    BRA.B	DECODE_DISPATCH                       | decode OS entries
DECODE_SHORT:
    AND.L	D2,D1                                 | D1 = low 7 bits
    BEQ.B	DECODE_NEXT                           | zero: skip (keep unimplemented)
    CMP.W	D2,D1                                 | is it $7F (escape)?
    BEQ.B	DECODE_ABSOLUTE                       | yes: read 4-byte absolute offset
    ADD.W	D1,D1                                 | double to get word offset
    BRA.B	DISP_ADD_DELTA                        | add delta to ROM ptr
DECODE_ABSOLUTE:
    MOVEQ.L	#0x3,D3                             | 4 bytes to read
DECODE_ABS_LOOP:
    ASL.L	#0x8,D1                               | shift accumulator left 8
    MOVE.B	(A0)+,D1                             | read next byte
    DBF.W	D3,DECODE_ABS_LOOP                    | loop for 4 bytes
    MOVEA.L	(ROMBase).W,A2                      | reset A2 to ROM base
    BRA.B	DISP_ADD_DELTA                        | add absolute offset
| ----------------------------------------------------------
| DECODE_DONE - dispatch table fully decoded; install A-line handler
| Selects between 68000 and 68010+ A-line trap handler based on CPU.
DECODE_DONE:
    MOVE.B	(CPUFlag).W,D1                       | D1 = CPU type (0/1/2)
    LEA.L	ATRAP68010(PC),A0                     | assume 68010 handler
    SUBQ.B	#0x1,D1                              | is it 68010?
    BEQ.B	INSTALL_ALINE                         | yes: use 68010 handler
    LEA.L	EMT1010(PC),A0                        | 68000: use A-line emulator trap
    BMI.B	INSTALL_ALINE                         | 68000 (D1 was 0, now -1): install it
    LEA.L	ATRAP68020(PC),A0                     | 68020+: use fast dispatch handler
INSTALL_ALINE:
    MOVE.L	A0,(ATrapVector).W                   | install A-line trap handler vector
    RTS                                         | return from INITDISPATCHER
| ----------------------------------------------------------
| P_tUnimplemented - handler for unimplemented A-line traps
| Called when an application uses a trap not in this ROM.
| Generates system error #12 (dsNoPk = unimplemented trap).
P_tUnimplemented:
    MOVEQ.L	#0xC,D0                             | D0 = 12 (dsNoPk: unimplemented trap)
    BRA.W	SYSTEMERROR                           | display system error dialog
| ----------------------------------------------------------
| INITIOMGR - allocate Unit Table, open ROM drivers, load SERD
| Allocates a 64-entry Unit Table, opens .Sony and .Sound drivers,
| then loads and executes the SERD 0 resource (serial drivers).
INITIOMGR:
    MOVEQ.L	#0x40,D0                            | D0 = 64 unit table entries
    MOVE.W	D0,(UnitTableEntryCount).W           | store entry count
    ASL.L	#0x2,D0                               | D0 = 64 * 4 = 256 bytes
    _NewPtrSysClear                             | allocate cleared Unit Table
    MOVE.L	A0,(UTableBase).W                    | store Unit Table base address
    SUBA.W	#0x32,A7                             | allocate IOParam block (50 bytes)
    MOVEA.L	A7,A0                               | A0 = IOParam block
    CLR.B	0x1B(A0)                              | ioPermssn = 0 (default)
    LEA.L	DT_SONY_NAME(PC),A1                   | A1 -> Pascal string "\x05.Sony"
    MOVE.L	A1,0x12(A0)                          | ioFileName = .Sony name
    _Open                                       | open .Sony disk driver
    LEA.L	DT_SOUND_NAME(PC),A1                  | A1 -> Pascal string "\x06.Sound "
    MOVE.L	A1,0x12(A0)                          | ioFileName = .Sound name
    _Open                                       | open .Sound driver
    ADDA.W	#0x32,A7                             | free IOParam block
| Load and execute the serial driver resource ('SERD' 0)
    SUBQ.W	#0x4,A7                              | room for Handle result
    MOVE.L	#0x53455244,-(A7)                    | push resource type 'SERD'
    CLR.W	-(A7)                                 | push resource ID 0
    MOVE.W	#0xFFFF,(ROMMapInsert).W             | force search ROM resource map
    _GetResource                                | load SERD 0 resource
    MOVE.L	(A7)+,D0                             | D0 = handle (or nil)
    BEQ.B	INIT_IOMGR_DONE                       | not found: skip serial init
    MOVEA.L	D0,A0                               | A0 = handle
    MOVEA.L	(A0),A0                             | A0 = dereference -> code ptr
    JSR	(A0)                                    | execute SERD init (installs serial drivers)
INIT_IOMGR_DONE:
    RTS                                         | return from INITIOMGR
| DT_SONY_NAME - Pascal string ".Sony" (floppy disk driver)
DT_SONY_NAME:
    .byte 0x05                                  | string length
    .ascii ".Sony"                              | driver name
| DT_SOUND_NAME - Pascal string ".Sound " (sound driver, padded)
DT_SOUND_NAME:
    .byte 0x06                                  | string length
    .ascii ".Sound "                            | driver name (padded to even)
| ----------------------------------------------------------
| INITMEMMGR - initialize Memory Manager low-memory globals
INITMEMMGR:
    MOVE.L	#0xFFFFFF,(Lo3Bytes).W               | Lo3Bytes = $00FFFFFF (24-bit addr mask)
    MOVE.L	#0x400,(MinStack).W                  | MinStack = 1K minimum stack
    MOVE.L	#0x2000,(DefltStack).W               | DefltStack = 8K default stack
    CLR.W	(MMDefFlags).W                        | no Memory Manager flags
    RTS                                         | return from INITMEMMGR
| ----------------------------------------------------------
| INITRSRCMGR - initialize Resource Manager (ROM resource map)
INITRSRCMGR:
    ST.B	(SysMap).W                             | SysMap = true (system map exists)
    CLR.L	(TopMapHndl).W                        | no top resource map yet
    CLR.W	-(A7)                                 | push result space
    _InitResources                              | init Resource Manager, load ROM map
    ADDQ.W	#0x2,A7                              | pop result
    RTS                                         | return from INITRSRCMGR
| ----------------------------------------------------------
| INITTIMERMGR - initialize Time Manager
| Allocates 18 bytes for timer variables, inits the timer queue.
INITTIMERMGR:
    MOVEQ.L	#0x12,D0                            | D0 = 18 bytes for timer vars
    _NewPtrSysClear                             | allocate timer variable block
    MOVE.L	A0,(TimeVars).W                      | store timer vars pointer
    LEA.L	0x8(A0),A1                            | A1 = timer queue header (offset 8)
    JSR	INITQUEUE(PC)                           | init timer queue (empty)
    RTS                                         | return from INITTIMERMGR
