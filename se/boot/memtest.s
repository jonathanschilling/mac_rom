| Startup tests: RAM test, Test Manager, SysBeep/BootBeep
|
| Apple sources: the startup test code (System 7.1: USTStartUp.a,
| USTTestMgr.a and their includes; MacSEROM.lst lists these routines in
| the SYSTEMERROR module, as it starts no new module for them). In ROM
| order: the MEMTEST exception vector table and its handlers (BUSERROR
| ... EXCEPTIONHANDLER), STARTTEST1 (cold/warm start continuation, ROM
| checksum, RAM sizing and testing), RAMTEST, the manufacturing Test
| Manager (TESTMANAGER, TMRESTART ...), SYSTEMBEEP (the _SysBeep trap,
| $A9C8), BOOTBEEP and the ERRORBEEP return stubs.
|
| STARTTEST1 implements the power-on self-test (POST) sequence:
|   1. Check for manufacturing test software intercept (TestSoftare)
|   2. Set up VIA port A and look for the factory loopback jumper
|   3. Verify ROM checksum (256 KB, sum of 16-bit words)
|   4. Access the SCSI chip and the IWM
|   5. Jump to FDHD cold-start patch in upper ROM
|   6. Test first 1K of RAM (pattern fill/verify)
|   7. Detect installed RAM size
|   8. Run address line stuck-at test
|   9. With the loopback jumper: enter the diagnostic Test Manager
|      (serial port)
|  10. Otherwise: install MEMTEST as the exception vector table
|      (copy it to address 0), continue boot
|
| The Test Manager (TESTMANAGER/TMRESTART) is a serial-port command
| interpreter used by Apple manufacturing test stations. It accepts
| single-character commands over SCC channel B (modem port):
|   *S = start test, *L = load address, *B = byte count, *D = data,
|   *C = checksum, *G = go (execute), *0/*1 = set A0/A1 range,
|   *4 = reset, *5 = enable beep, *R = report, *M = memory dump,
|   *E = echo on, *I = reinit, *T = run test by number
|
| Register conventions:
|   D6 = error accumulator (0 = no errors, non-zero = failure code)
|   D7 = status/flags bitfield:
|     bits 0-7:  test phase number / iteration count
|     bit 16:    timer beep enabled
|     bit 17:    SCC serial port initialized
|     bit 18:    alternate serial polling mode
|     bit 19:    command prefix '*' received
|     bit 20:    hex display mode (nibbles vs bytes)
|     bit 21:    serial echo enabled
|     bit 22:    timer beep auto-reload
|     bit 23:    append CR/LF after output
|     bit 24:    error flag (triggers Sad Mac on check; Apple's STEqu.a:
|                excp, "unexpected exception received")
|     bit 25:    STEqu.a: nmi, "the NMI switch was hit" (set by INTLEVEL7)
|     bit 26:    factory loopback jumper found (STEqu.a: test, "the
|                VIA loopback was found")
|     bit 27:    STEqu.a: beok, "a BusError is expected and is OK"
|     bit 28:    loop on error
|     bit 29:    repeat on error
|     bit 30:    report results after test
|     bit 31:    reset on completion
|   A6 = return address (used instead of stack before RAM is trusted)
| -------------------------------------------------------------------------

| ----------------------------------------------------------
| MEMTEST - exception vector table of the startup tests: 64 vectors in
| 68000 order, each pointing at one of the handlers that follow the table.
| Apple source: TMVectors in USTStartUp.a (System 7.1), the same table
| with the same handlers ("used by the Ikki Test Manager and the power up
| test code"); MacSEROM.lst: MEMTEST. A 68000 always takes its vectors
| from address 0, so after the first startup tests the start code copies
| the table there (COLDSTART_MEMTEST_COPYLOOP; Apple: "They are copied to
| RAM after completion of the first set of power up tests"). The vectors
| stay in effect until SYSERRINIT (debugger/debugger.s) installs the
| system's handlers. The entries for vectors 0 and 1 are placeholders
| (Apple: "space for initial SP/PC"): a reset reads the ROM header.
| Vectors 13, 14 and 48-58 belong to the 68010/68020 and their
| coprocessors; the SE's 68000 never takes them.
MEMTEST:
    .long	0x00002000                            | $00 vector 0: initial SSP (placeholder)
    .long	STARTTEST1-BASEOFROM+0x400000         | $04 vector 1: initial PC (placeholder)
    .long	BUSERROR-BASEOFROM+0x400000           | $08 vector 2: bus error
    .long	ADRERROR-BASEOFROM+0x400000           | $0C vector 3: address error
    .long	ILLERROR-BASEOFROM+0x400000           | $10 vector 4: illegal instruction
    .long	ZERERROR-BASEOFROM+0x400000           | $14 vector 5: zero divide
    .long	CHKERROR-BASEOFROM+0x400000           | $18 vector 6: CHK instruction
    .long	XTRAPX-BASEOFROM+0x400000             | $1C vector 7: TRAPV instruction
    .long	PRIVERROR-BASEOFROM+0x400000          | $20 vector 8: privilege violation
    .long	TRACE-BASEOFROM+0x400000              | $24 vector 9: trace
    .long	LINEA-BASEOFROM+0x400000              | $28 vector 10: line 1010 emulator (A-line)
    .long	LINEF-BASEOFROM+0x400000              | $2C vector 11: line 1111 emulator (F-line)
    .long	NOTASS-BASEOFROM+0x400000             | $30 vector 12: unassigned
    .long	CPPROTOCOL-BASEOFROM+0x400000         | $34 vector 13: coprocessor protocol violation
    .long	FORMATX-BASEOFROM+0x400000            | $38 vector 14: format error
    .long	SPURINTERRUPT-BASEOFROM+0x400000      | $3C vector 15: uninitialized interrupt
    .long	NOTASS-BASEOFROM+0x400000             | $40 vector 16: unassigned
    .long	NOTASS-BASEOFROM+0x400000             | $44 vector 17: unassigned
    .long	NOTASS-BASEOFROM+0x400000             | $48 vector 18: unassigned
    .long	NOTASS-BASEOFROM+0x400000             | $4C vector 19: unassigned
    .long	NOTASS-BASEOFROM+0x400000             | $50 vector 20: unassigned
    .long	NOTASS-BASEOFROM+0x400000             | $54 vector 21: unassigned
    .long	NOTASS-BASEOFROM+0x400000             | $58 vector 22: unassigned
    .long	NOTASS-BASEOFROM+0x400000             | $5C vector 23: unassigned
    .long	SPURINTERRUPT-BASEOFROM+0x400000      | $60 vector 24: spurious interrupt
    .long	INTLEVEL1-BASEOFROM+0x400000          | $64 vector 25: level 1 interrupt
    .long	INTLEVEL2-BASEOFROM+0x400000          | $68 vector 26: level 2 interrupt
    .long	INTLEVEL3-BASEOFROM+0x400000          | $6C vector 27: level 3 interrupt
    .long	INTLEVEL4-BASEOFROM+0x400000          | $70 vector 28: level 4 interrupt
    .long	INTLEVEL5-BASEOFROM+0x400000          | $74 vector 29: level 5 interrupt
    .long	INTLEVEL6-BASEOFROM+0x400000          | $78 vector 30: level 6 interrupt
    .long	INTLEVEL7-BASEOFROM+0x400000          | $7C vector 31: level 7 interrupt (NMI)
    .long	TRAPN-BASEOFROM+0x400000              | $80 vector 32: TRAP #0
    .long	TRAPN-BASEOFROM+0x400000              | $84 vector 33: TRAP #1
    .long	TRAPN-BASEOFROM+0x400000              | $88 vector 34: TRAP #2
    .long	TRAPN-BASEOFROM+0x400000              | $8C vector 35: TRAP #3
    .long	TRAPN-BASEOFROM+0x400000              | $90 vector 36: TRAP #4
    .long	TRAPN-BASEOFROM+0x400000              | $94 vector 37: TRAP #5
    .long	TRAPN-BASEOFROM+0x400000              | $98 vector 38: TRAP #6
    .long	TRAPN-BASEOFROM+0x400000              | $9C vector 39: TRAP #7
    .long	TRAPN-BASEOFROM+0x400000              | $A0 vector 40: TRAP #8
    .long	TRAPN-BASEOFROM+0x400000              | $A4 vector 41: TRAP #9
    .long	TRAPN-BASEOFROM+0x400000              | $A8 vector 42: TRAP #10
    .long	TRAPN-BASEOFROM+0x400000              | $AC vector 43: TRAP #11
    .long	TRAPN-BASEOFROM+0x400000              | $B0 vector 44: TRAP #12
    .long	TRAPN-BASEOFROM+0x400000              | $B4 vector 45: TRAP #13
    .long	TRAPN-BASEOFROM+0x400000              | $B8 vector 46: TRAP #14
    .long	TRAPN-BASEOFROM+0x400000              | $BC vector 47: TRAP #15
    .long	FPCP1-BASEOFROM+0x400000              | $C0 vector 48: FPCP branch or set on unordered
    .long	FPCP2-BASEOFROM+0x400000              | $C4 vector 49: FPCP inexact result
    .long	FPCP3-BASEOFROM+0x400000              | $C8 vector 50: FPCP divide by zero
    .long	FPCP4-BASEOFROM+0x400000              | $CC vector 51: FPCP underflow
    .long	FPCP5-BASEOFROM+0x400000              | $D0 vector 52: FPCP operand error
    .long	FPCP6-BASEOFROM+0x400000              | $D4 vector 53: FPCP overflow
    .long	FPCP7-BASEOFROM+0x400000              | $D8 vector 54: FPCP signaling NAN
    .long	NOTASS-BASEOFROM+0x400000             | $DC vector 55: unassigned
    .long	PMMUCONFIG-BASEOFROM+0x400000         | $E0 vector 56: PMMU configuration
    .long	PMMUILLEGAL-BASEOFROM+0x400000        | $E4 vector 57: PMMU illegal operation
    .long	PMMUACCESS-BASEOFROM+0x400000         | $E8 vector 58: PMMU access level violation
    .long	NOTASS-BASEOFROM+0x400000             | $EC vector 59: unassigned
    .long	NOTASS-BASEOFROM+0x400000             | $F0 vector 60: unassigned
    .long	NOTASS-BASEOFROM+0x400000             | $F4 vector 61: unassigned
    .long	NOTASS-BASEOFROM+0x400000             | $F8 vector 62: unassigned
    .long	NOTASS-BASEOFROM+0x400000             | $FC vector 63: unassigned
| ----------------------------------------------------------
| Exception handlers of the startup tests, reached through MEMTEST
| (Apple source: the handlers after TMVectors in USTStartUp.a; the labels
| are Apple's names). Each stores $FF00 plus the exception number in
| D7.W and branches to EXCEPTIONHANDLER. The numbers follow Apple's
| STEqu.a, BECode (1, bus error) to PACode ($20, PMMU access violation);
| Apple's later ROMs keep them in the high byte of D7.W instead.
|
| BUSERROR - vector 2. A test that probes for hardware sets D7 bit 27
| (STEqu.a: beok, "a BusError is expected and is OK") and holds its SP in
| A5 and its return address in A6; the bus error then returns there.
| Any other bus error is exception 1.
BUSERROR:
    BTST	#0x1B,D7                               | D7 bit 27 (beok): bus error expected?
    BEQ.B	BUSERROR_UNEXPECTED                   | no: an unexpected bus error
    MOVEA.L	A5,A7                               | yes: SP of the probing code
    JMP	(A6)                                    | return to the probe (A6)
| The other handlers follow in vector order.
BUSERROR_UNEXPECTED:
    MOVE.W	#0xFF01,D7                           | D7.W = exception $01: bus error
    BRA.W	EXCEPTIONHANDLER                      | common exit
ADRERROR:
    MOVE.W	#0xFF02,D7                           | D7.W = exception $02: address error
    BRA.W	EXCEPTIONHANDLER                      | common exit
ILLERROR:
    MOVE.W	#0xFF03,D7                           | D7.W = exception $03: illegal instruction
    BRA.W	EXCEPTIONHANDLER                      | common exit
ZERERROR:
    MOVE.W	#0xFF04,D7                           | D7.W = exception $04: zero divide
    BRA.W	EXCEPTIONHANDLER                      | common exit
CHKERROR:
    MOVE.W	#0xFF05,D7                           | D7.W = exception $05: CHK instruction
    BRA.W	EXCEPTIONHANDLER                      | common exit
XTRAPX:
    MOVE.W	#0xFF06,D7                           | D7.W = exception $06: TRAPV instruction
    BRA.W	EXCEPTIONHANDLER                      | common exit
PRIVERROR:
    MOVE.W	#0xFF07,D7                           | D7.W = exception $07: privilege violation
    BRA.W	EXCEPTIONHANDLER                      | common exit
TRACE:
    MOVE.W	#0xFF08,D7                           | D7.W = exception $08: trace
    BRA.W	EXCEPTIONHANDLER                      | common exit
LINEA:
    MOVE.W	#0xFF09,D7                           | D7.W = exception $09: line A
    BRA.W	EXCEPTIONHANDLER                      | common exit
LINEF:
    MOVE.W	#0xFF0A,D7                           | D7.W = exception $0A: line F
    BRA.W	EXCEPTIONHANDLER                      | common exit
NOTASS:
    MOVE.W	#0xFF0B,D7                           | D7.W = exception $0B: unassigned vector
    BRA.W	EXCEPTIONHANDLER                      | common exit
CPPROTOCOL:
    MOVE.W	#0xFF0C,D7                           | D7.W = exception $0C: coprocessor protocol violation
    BRA.B	EXCEPTIONHANDLER                      | common exit
FORMATX:
    MOVE.W	#0xFF0D,D7                           | D7.W = exception $0D: format error
    BRA.B	EXCEPTIONHANDLER                      | common exit
SPURINTERRUPT:
    MOVE.W	#0xFF0E,D7                           | D7.W = exception $0E: spurious interrupt
    BRA.B	EXCEPTIONHANDLER                      | common exit
TRAPN:
    MOVE.W	#0xFF0F,D7                           | D7.W = exception $0F: TRAP #n
    BRA.B	EXCEPTIONHANDLER                      | common exit
INTLEVEL1:
    MOVE.W	#0xFF10,D7                           | D7.W = exception $10: level 1 interrupt
    BRA.B	EXCEPTIONHANDLER                      | common exit
INTLEVEL2:
    MOVE.W	#0xFF11,D7                           | D7.W = exception $11: level 2 interrupt
    BRA.B	EXCEPTIONHANDLER                      | common exit
INTLEVEL3:
    MOVE.W	#0xFF12,D7                           | D7.W = exception $12: level 3 interrupt
    BRA.B	EXCEPTIONHANDLER                      | common exit
INTLEVEL4:
    MOVE.W	#0xFF13,D7                           | D7.W = exception $13: level 4 interrupt
    BRA.B	EXCEPTIONHANDLER                      | common exit
INTLEVEL5:
    MOVE.W	#0xFF14,D7                           | D7.W = exception $14: level 5 interrupt
    BRA.B	EXCEPTIONHANDLER                      | common exit
INTLEVEL6:
    MOVE.W	#0xFF15,D7                           | D7.W = exception $15: level 6 interrupt
    BRA.B	EXCEPTIONHANDLER                      | common exit
INTLEVEL7:
    MOVE.W	#0xFF16,D7                           | D7.W = exception $16: level 7 interrupt (NMI)
    BSET	#0x19,D7                               | D7 bit 25 (nmi): the NMI switch was pressed
    BRA.B	EXCEPTIONHANDLER                      | common exit
FPCP1:
    MOVE.W	#0xFF17,D7                           | D7.W = exception $17: FPCP unordered condition
    BRA.B	EXCEPTIONHANDLER                      | common exit
FPCP2:
    MOVE.W	#0xFF18,D7                           | D7.W = exception $18: FPCP inexact result
    BRA.B	EXCEPTIONHANDLER                      | common exit
FPCP3:
    MOVE.W	#0xFF19,D7                           | D7.W = exception $19: FPCP divide by zero
    BRA.B	EXCEPTIONHANDLER                      | common exit
FPCP4:
    MOVE.W	#0xFF1A,D7                           | D7.W = exception $1A: FPCP underflow
    BRA.B	EXCEPTIONHANDLER                      | common exit
FPCP5:
    MOVE.W	#0xFF1B,D7                           | D7.W = exception $1B: FPCP operand error
    BRA.B	EXCEPTIONHANDLER                      | common exit
FPCP6:
    MOVE.W	#0xFF1C,D7                           | D7.W = exception $1C: FPCP overflow
    BRA.B	EXCEPTIONHANDLER                      | common exit
FPCP7:
    MOVE.W	#0xFF1D,D7                           | D7.W = exception $1D: FPCP signaling NAN
    BRA.B	EXCEPTIONHANDLER                      | common exit
PMMUCONFIG:
    MOVE.W	#0xFF1E,D7                           | D7.W = exception $1E: PMMU configuration
    BRA.B	EXCEPTIONHANDLER                      | common exit
PMMUILLEGAL:
    MOVE.W	#0xFF1F,D7                           | D7.W = exception $1F: PMMU illegal operation
    BRA.B	EXCEPTIONHANDLER                      | common exit
PMMUACCESS:
    MOVE.W	#0xFF20,D7                           | D7.W = exception $20: PMMU access level violation, falls through
| ----------------------------------------------------------
| EXCEPTIONHANDLER - common exit of the handlers (Apple: ExceptionHandler;
| the 1992 version goes to CritErr instead). Sets D7 bit 24 (STEqu.a:
| excp, "unexpected exception received"). After an NMI (D7 bit 25) it
| shows the sad Mac at once; otherwise it returns with RTE, and the test
| code, which checks bit 24, branches to the sad Mac itself.
| Called by: BUSERROR_UNEXPECTED, ADRERROR, ILLERROR, ZERERROR, CHKERROR (and 26 more)
EXCEPTIONHANDLER:
    BSET	#0x18,D7                               | D7 bit 24 (excp): unexpected exception
    BTST	#0x19,D7                               | D7 bit 25 (nmi): NMI switch pressed?
    BEQ.B	EXCEPTIONHANDLER_RTE                  | no: return to the test code
    MOVEA.W	#0x2000,A7                          | yes: fresh stack at $2000
    JMP	P_SadMac(PC)                            | sad Mac
EXCEPTIONHANDLER_RTE:
    RTE                                         | back to the test code, which checks bit 24



STARTTEST1:
    MOVE.W	#0x2700,SR                           | supervisor mode, IPL=7 (mask all interrupts)
    MOVEA.W	#0x2000,A7                          | set initial stack pointer at 8K
    MOVEQ.L	#0x0,D7                             | clear status/flags register
    MOVEQ.L	#0x0,D6                             | clear error accumulator
    MOVE.L	#0x55AAAA55,D1                       | D1 = TestSoftare magic cookie
    MOVE.L	(TestSoftare).L,D0                   | D0 = low-memory test software signature
    CMP.L	D1,D0                                 | manufacturing test software installed?
    BNE.B	COLDSTART_NO_TEST_SW                  | no: continue normal cold start
    MOVEM.L	(TestSoftare).L,D0/A0               | D0 = cookie, A0 = test entry point
    JMP	(A0)                                    | jump to manufacturing test software
COLDSTART_NO_TEST_SW:
    BCLR	#0x1B,D7                               | clear bit 27 (beok: a bus error is expected)
    MOVEQ.L	#0x0,D1                             | clear D1
    MOVE.W	#0x6,D7                              | D7 = 6 (initial test phase)
    LEA.L	(VIA_Base).L,A1                       | A1 = VIA base address
    MOVE.B	#0x9,0x600(A1)                       | VIA DDRA = $09: PA0 and PA3 outputs (STEqu.a V1DDRA)
    MOVE.B	0x1E00(A1),D0                        | D0 = VIA port A (vBufA)
    BSET	#0x3,D0                                | PA3 = 1: vSync, synchronous modem off
    MOVE.B	D0,0x1E00(A1)                        | write port A
    BTST	#0x18,D7                               | check error flag (bit 24)
    BNE.W	P_SadMac                              | error: Sad Mac
| Factory loopback check (Apple's CheckLoopBack in USTStartUp.a: "On
| Mac,MacPP,NuMac the jumper shorts SV2 to SV1"): drive VIA PA0 (sound
| volume bit 0, SV1) low and high and see whether PA1 (SV2, an input
| after DDRA = $09) follows. If it does, D7 bit 26 (STEqu.a: test, "the
| VIA loopback was found") is set and the ROM runs the Test Manager
| instead of booting. This is not a floppy controller test.
    LEA.L	(VIA_Base).L,A2                       | A2 = VIA base address
    MOVE.B	0x1E00(A2),D0                        | D0 = VIA port A (vBufA)
    BCLR	#0x0,D0                                | PA0 (SV1) = 0
    MOVE.B	D0,0x1E00(A2)                        | write port A
    MOVE.B	0x1E00(A2),D0                        | read port A back
    BTST	#0x1,D0                                | PA1 (SV2) still 1?
    BNE.B	COLDSTART_RUN_CHECKSUM                | yes: not shorted, no loopback
    BSET	#0x0,D0                                | PA0 (SV1) = 1
    MOVE.B	D0,0x1E00(A2)                        | write port A
    MOVE.B	0x1E00(A2),D0                        | read port A back
    BTST	#0x1,D0                                | PA1 (SV2) followed?
    BEQ.B	COLDSTART_RUN_CHECKSUM                | no: no loopback
    BSET	#0x1A,D7                               | D7 bit 26 (test): loopback jumper found
COLDSTART_RUN_CHECKSUM:
    MOVE.W	#0x1,D7                              | D7 = 1 (test phase 1: ROM checksum)
    LEA.L	COLDSTART_CHECKSUM_DONE(PC),A6        | set return address for checksum
    JMP	P_ChecksumRom(PC)                       | verify 256 KB ROM checksum
COLDSTART_CHECKSUM_DONE:
    TST.L	D6                                    | check checksum result (D6 from P_ChecksumRom)
    BNE.W	P_SadMac                              | checksum failed: Sad Mac
    CLR.W	D7                                    | clear test phase
    LEA.L	(0x5FF000).L,A2                       | A2 = SCSI base (NCR 5380 at $5FF000 on the SE)
    MOVE.B	0x10(A2),D0                          | access the 5380 (register 1: initiator command)
    BTST	#0x18,D7                               | check error flag (bit 24, excp)
    BNE.W	P_SadMac                              | error: Sad Mac
    LEA.L	(IWM_Base).L,A2                       | A2 = IWM base ($DFE1FF)
    TST.B	q7L(A2)                               | access the IWM: q7L (L7 = 0)
    MOVE.B	q6H(A2),D0                           | q6H (L6 = 1; an H address: the IWM drives no data)
    BTST	#0x18,D7                               | check error flag (bit 24, excp)
    BNE.W	P_SadMac                              | error: Sad Mac
| RAM test (phase 14): P_CheckRamFirst8 returns via A6 with the error
| bits in D6. The SE FDHD routes the call through a patch in its tail
| area ($43D034 -> $43DD36): the patch fetches the self-relative offset
| of P_CheckRamFirst8 stored after the JMP (MOVEA.W (A6)+,A0 / ADDA.L
| A6,A0), reads each of the four 1 MB RAM banks once, sets D7 = 14 and
| jumps to P_CheckRamFirst8 with A6 = MEMTEST_RAM_RET.
| --- ROM-variant difference @ $1C9C ---
| SE:      MOVE.W #14,D7 / LEA MEMTEST_RAM_RET(PC),A6 / JMP P_CheckRamFirst8(PC)
| SE FDHD: LEA FDHD_RAMTEST_OFFSET(PC),A6 / JMP $43D034 / DC.W offset
| Reason: the SE FDHD touches all RAM banks before this RAM test
.if ROM_TARGET == MAC_SE
    MOVE.W	#0xE,D7                              | D7 = 14 (test phase)
    LEA.L	MEMTEST_RAM_RET(PC),A6                | A6 = return address
    JMP	P_CheckRamFirst8(PC)                    | test RAM, return to MEMTEST_RAM_RET
.else
FDHD_ColdStartPatchHook:
    LEA.L	FDHD_RAMTEST_OFFSET(PC),A6            | A6 -> offset word (return address - 2)
    JMP	(0x43D034).L                            | FDHD patch: touch RAM banks, then RAM test
FDHD_RAMTEST_OFFSET:
    .short	P_CheckRamFirst8-MEMTEST_RAM_RET     | self-relative offset, read by the patch
.endif
MEMTEST_RAM_RET:
    TST.L	D6                                    | RAM test error bits
    BNE.W	P_SadMac                              | RAM failed: Sad Mac
    BTST	#0x18,D7                               | check error flag
    BNE.W	P_SadMac                              | error: Sad Mac
    MOVE.W	#0x2,D7                              | D7 = 2 (test phase 2: initial RAM test)
    SUBA.L	A0,A0                                | A0 = 0 (RAM base address)
    LEA.L	(DispatchTab).W,A1                    | A1 = 0x400 (1K = end of initial test range)
    LEA.L	COLDSTART_INIT_RAM_DONE(PC),A6        | set return address for RAM test
| Check first 1K of RAM with pattern fill/verify
    JMP	P_TestMemory0(PC)                       | test first 1K of RAM
COLDSTART_INIT_RAM_DONE:
    TST.L	D6                                    | check RAM test result
    BNE.W	P_SadMac                              | RAM test failed: Sad Mac
    BTST	#0x18,D7                               | check error flag
    BNE.W	P_SadMac                              | error: Sad Mac
    CLR.W	D7                                    | clear test phase
    LEA.L	COLDSTART_MEMSIZE_DONE(PC),A6         | set return address for memory sizing
    JMP	P_FindMemorySize(PC)                    | detect installed RAM size
COLDSTART_MEMSIZE_DONE:
    MOVEA.L	D6,A7                               | set stack to top of detected RAM
    MOVEQ.L	#0x0,D6                             | clear error accumulator
    MOVE.W	#0x5,D7                              | D7 = 5 (test phase 5: address lines)
    LEA.L	COLDSTART_ADDRLINE_DONE(PC),A6        | set return address
    JMP	ADDRTEST_LINES(PC)                      | run address line stuck-at test
COLDSTART_ADDRLINE_DONE:
    TST.L	D6                                    | check address line test result
    BNE.W	P_SadMac                              | address line test failed: Sad Mac
    CLR.W	D7                                    | clear test phase (high word preserved)
    BTST	#0x1A,D7                               | loopback jumper found? (bit 26 in high word)
    BNE.B	COLDSTART_LOOPBACK_PATH               | yes: enter test manager path
| Normal start: install MEMTEST as the exception vector table by copying
| its 64 vectors to address 0 (a 68000 takes its vectors from there),
| then continue at STARTINIT1 with A6 = top of RAM.
    MOVEA.L	A7,A6                               | A6 = top of RAM (SP was set to it above)
    MOVEA.W	#0x400,A7                           | temporary stack at $400
    LEA.L	MEMTEST(PC),A0                        | A0 = the vector table in ROM
    SUBA.L	A1,A1                                | A1 = 0: the exception vectors
    MOVE.W	#0x40,D0                             | 64 vectors
    SUBQ.W	#0x1,D0                              | minus 1 for DBF
COLDSTART_MEMTEST_COPYLOOP:
    MOVE.L	(A0)+,(A1)+                          | copy one vector
    DBF.W	D0,COLDSTART_MEMTEST_COPYLOOP         | 64 times
    JMP	STARTINIT1(PC)                          | continue boot init (boot_install.s)
| loopback jumper (factory test fixture) found: enable diagnostic beep
| and enter test manager.
| The test manager loop handles manufacturing test sequences via serial.
COLDSTART_LOOPBACK_PATH:
    BSET	#0x10,D7                               | set bit 16: enable timer beep
    BSET	#0x16,D7                               | set bit 22: timer beep auto-reload
    TST.W	D7                                    | test low word of D7
    BNE.B	COLDSTART_DIAG_TIMER_INIT             | non-zero: skip diagnostic error code
    MOVE.L	#0x87654321,D6                       | D6 = diagnostic error (unexpected state)
COLDSTART_DIAG_TIMER_INIT:
    MOVE.W	#0xC,D4                              | D4 low = 12 (timer reload count)
    SWAP.W	D4                                   | move to high word for countdown
    LEA.L	COLDSTART_RUN_TM(PC),A6               | set return address for timer init
    JMP	VIA_T1_INIT_BEEP(PC)                    | init VIA Timer 1 for boot beep
COLDSTART_RUN_TM:
    JMP	TMRESTART(PC)                           | enter diagnostic test manager
| RAMTEST - callable RAM test routine
|
| Tests a RAM range by splitting at the 512K or 2MB boundary and
| testing each segment with P_TestMemory0 (pattern fill/verify).
| Entry: A0 = start address, A1 = end address, A6 = RAM end
| Exit: D6 = error code (0 = pass), registers preserved
RAMTEST:
    MOVEM.L	D0-D7/A0-A6,-(A7)                   | save all registers
    MOVE.W	SR,-(A7)                             | save status register
    MOVEQ.L	#0x0,D7                             | clear test flags
    MOVE.W	#0x2700,SR                           | supervisor mode, IPL=7 (mask all interrupts)
    MOVE.L	A6,D0                                | D0 = RAM end address
    LEA.L	(0x80000).L,A2                        | A2 = 512K (default split point)
    CMPI.L	#0x100000,D0                         | RAM > 1MB?
    BLE.B	RAMTEST_USE_512K_SPLIT                | no: use 512K split
    LEA.L	(0x200000).L,A2                       | yes: use 2MB split point
RAMTEST_USE_512K_SPLIT:
    CMPA.L	A0,A1                                | end <= start?
    BLE.B	RAMTEST_RETURN                        | nothing to test: return
    MOVEQ.L	#0x0,D6                             | clear error accumulator
    MOVE.W	#0x3,D7                              | D7 = 3 (test phase 3: first segment)
    CMPA.L	A1,A2                                | split point >= end?
    BGE.B	RAMTEST_RUN_SEGMENT                   | yes: test whole range in one pass
    CMPA.L	A0,A2                                | split point <= start?
    BLE.B	RAMTEST_SECOND_HALF                   | yes: skip to second segment
    MOVEM.L	A0-A2,-(A7)                         | save range pointers
    MOVEA.L	A2,A1                               | A1 = split (test base..split first)
    LEA.L	RAMTEST_FIRST_HALF_DONE(PC),A6        | set return address
    JMP	P_TestMemory0(PC)                       | test first segment
RAMTEST_FIRST_HALF_DONE:
    TST.L	D6                                    | check first segment result
    BNE.B	P_SadMac                              | first segment failed: Sad Mac
    MOVEM.L	(A7)+,A0-A2                         | restore range pointers
    MOVEA.L	A2,A0                               | A0 = split (start of second half)
RAMTEST_SECOND_HALF:
    MOVE.W	#0x4,D7                              | D7 = 4 (test phase 4: second segment)
RAMTEST_RUN_SEGMENT:
    LEA.L	RAMTEST_SEGMENT_DONE(PC),A6           | set return address
    JMP	P_TestMemory0(PC)                       | test segment (pattern fill/verify)
RAMTEST_SEGMENT_DONE:
    TST.L	D6                                    | check segment result
    BNE.B	P_SadMac                              | segment failed: Sad Mac
RAMTEST_RETURN:
    MOVE.W	(A7)+,SR                             | restore status register
    MOVEM.L	(A7)+,D0-D7/A0-A6                   | restore all registers
    RTS                                         | return from RAMTEST
| P_SadMac - error handler
|
| Normally: jumps to CRITERR to display Sad Mac screen.
| With the factory loopback jumper (D7 bit 26): restarts the diagnostic
| test manager so the manufacturing test station can read the error
| code via serial.
| Called by: COLDSTART_CHECKSUM_DONE, FDHD_ColdStartPatchHook, COLDSTART_INIT_RAM_DONE, EXCEPTIONHANDLER, COLDSTART_NO_TEST_SW (and 3 more)
P_SadMac:
    BTST	#0x1A,D7                               | loopback jumper (test fixture) found?
    BNE.B	P_SADMAC_TESTMGR                      | yes: restart test manager
    JMP	CRITERR(PC)                             | no: display Sad Mac error screen
P_SADMAC_TESTMGR:
    JMP	TMRESTART(PC)                           | restart diagnostic test manager
| TESTMANAGER - hardware test dispatcher
|
| Callable entry point for the manufacturing test infrastructure.
| D0 selects the function:
|   0 = init from param block at (A0), dispatch by test number
|   1 = return (done)
|   2 = return, discard saved SR
|   3 = reset state (clear D6/D7)
|   4 = continue existing test (dispatch by D7 test number)
|   5 = init from param block, then run tests by D7 bit mask
|   6 = run tests by D7 bits 8-15
| Param block at (A0): +0 = D7 flags, +4 = A0 start, +8 = A1 end
| D7 bits 8-15 select which of 8 test routines to run (via TEST_DISPATCH_TBL).
TESTMANAGER:
    MOVEM.L	D0-D7/A0-A6,-(A7)                   | save all registers
    MOVE.W	SR,-(A7)                             | save status register
    MOVE.W	#0x2700,SR                           | supervisor mode, IPL=7 (mask all interrupts)
    TST.W	D0                                    | selector = 0? (init + dispatch)
    BEQ.B	TM_SEL0_INIT                          | yes: init from param block
    SUBQ.W	#0x1,D0                              | selector = 1?
    BEQ.W	TM_RETURN                             | yes: return (done)
    SUBQ.W	#0x1,D0                              | selector = 2?
    BEQ.W	TM_SEL2_RETURN_NO_SR                  | yes: return, discard saved SR
    SUBQ.W	#0x1,D0                              | selector = 3?
    BEQ.W	TM_SEL3_RESET_STATE                   | yes: reset state
    SUBQ.W	#0x1,D0                              | selector = 4?
    BEQ.B	TM_SEL4_DISPATCH_TEST                 | yes: continue (dispatch by test #)
    SUBQ.W	#0x1,D0                              | selector = 5?
    BEQ.W	TM_SEL5_INIT_BITMASK                  | yes: init + run by bit mask
    SUBQ.W	#0x1,D0                              | selector = 6?
    BEQ.W	TM_SEL6_BITMASK_LOOP                  | yes: run tests by bit mask
    BRA.W	TM_RETURN                             | unknown selector: return
| Selector 0: init from parameter block at (A0)
TM_SEL0_INIT:
    MOVEQ.L	#0x0,D6                             | clear error accumulator
    MOVE.L	(A0),D7                              | D7 = flags/test-select from param block
    MOVEA.L	0x8(A0),A1                          | A1 = end address from param block
    MOVEA.L	0x4(A0),A0                          | A0 = start address from param block
| Selector 4: dispatch single test by test number in D7 bits 8-15
TM_SEL4_DISPATCH_TEST:
    MOVE.W	D7,D1                                | D1 = D7 low word (flags + test select)
    LSR.W	#0x8,D1                               | D1 = test number (bits 8-15 >> 8)
    CMP.W	TEST_TABLE_COUNT(PC),D1               | test number within table bounds?
    BGE.W	TM_RETURN                             | out of range: return
    ASL.W	#0x1,D1                               | D1 *= 2 (word index into dispatch table)
    LEA.L	TEST_DISPATCH_TBL(PC),A5              | A5 = test dispatch table base
    MOVE.W	0x0(A5,D1.W),D1                      | D1 = PC-relative offset to test routine
    LEA.L	0x0(A5,D1.W),A5                       | A5 = test routine address
| Test iteration loop: run test via A5, check result, repeat per D7
TM_ITER_LOOP:
    LEA.L	TM_ITER_RESULT(PC),A6                 | set return address
    JMP	(A5)                                    | call test routine via dispatch table
TM_ITER_RESULT:
    TST.L	D6                                    | test passed? (D6 = 0 means pass)
    BEQ.B	TM_ITER_DEC                           | pass: continue to next iteration
    BTST	#0x1D,D7                               | repeat-on-error flag set? (bit 29)
    BEQ.B	TM_ITER_CHK_LOOP_ON_ERR               | no: check loop-on-error
TM_ITER_REPEAT_FOREVER:
    LEA.L	TM_ITER_REPEAT_FOREVER(PC),A6         | re-run forever: set return to self
    JMP	(A5)                                    | re-run same test (infinite retry)
TM_ITER_CHK_LOOP_ON_ERR:
    BTST	#0x1C,D7                               | loop-on-error flag set? (bit 28)
    BNE.B	TM_TEST_COMPLETE                      | yes: skip to test-complete
TM_ITER_DEC:
    SUBQ.B	#0x1,D7                              | decrement iteration count (low byte)
    BNE.B	TM_ITER_LOOP                          | more iterations: re-run test
| All iterations complete (or loop-on-error exit)
TM_TEST_COMPLETE:
    BTST	#0x1E,D7                               | report-results flag set? (bit 30)
    BEQ.B	TM_CHK_RESET                          | no: skip beep report
    LEA.L	TM_CHK_RESET(PC),A6                   | set return address
    JMP	DFAC_BEEP_TONE(PC)                      | generate result beep tone
TM_CHK_RESET:
    BTST	#0x1F,D7                               | reset-on-complete flag? (bit 31)
    BEQ.W	TM_RETURN                             | no: normal return
    RESET                                       | yes: reset all peripherals
TM_JUMP_RESET_VEC:
    MOVEA.L	(ResetVector).W,A0                  | A0 = system reset vector
    JMP	(A0)                                    | jump to reset handler
| Selector 5: init from param block, then run tests by bit mask
TM_SEL5_INIT_BITMASK:
    MOVEQ.L	#0x0,D6                             | clear error accumulator
    MOVE.L	(A0),D7                              | D7 = flags from param block
    MOVEA.L	0x8(A0),A1                          | A1 = end address from param block
    MOVEA.L	0x4(A0),A0                          | A0 = start address from param block
| Selector 6: run tests by D7 bit mask (bits 8-15 = tests 0-7)
| Each bit selects a test routine via TEST_DISPATCH_TBL. Tests run in order
| from bit 8 (test 0) through bit 15 (test 7), skipping unset bits.
TM_SEL6_BITMASK_LOOP:
    BTST	#0x8,D7                                | test 0 selected? (bit 8)
    BEQ.B	TM_BIT1_CHECK                         | no: skip to test 1
    MOVEQ.L	#0x0,D1                             | D1 = 0 (test 0 index)
    LEA.L	TM_BIT0_RESULT(PC),A6                 | set return address
    BRA.W	TM_DISPATCH_BY_INDEX                  | dispatch test 0
TM_BIT0_RESULT:
    TST.L	D6                                    | test 0 passed?
    BNE.W	TM_TEST_ERROR                         | failed: handle error
TM_BIT1_CHECK:
    BTST	#0x9,D7                                | test 1 selected? (bit 9)
    BEQ.B	TM_BIT2_CHECK                         | no: skip to test 2
    MOVEQ.L	#0x1,D1                             | D1 = 1 (test 1 index)
    LEA.L	TM_BIT1_RESULT(PC),A6                 | set return address
    BRA.B	TM_DISPATCH_BY_INDEX                  | dispatch test 1
TM_BIT1_RESULT:
    TST.L	D6                                    | test 1 passed?
    BNE.W	TM_TEST_ERROR                         | failed: handle error
TM_BIT2_CHECK:
    BTST	#0xA,D7                                | test 2 selected? (bit 10)
    BEQ.B	TM_BIT3_CHECK                         | no: skip to test 3
    MOVEQ.L	#0x2,D1                             | D1 = 2 (test 2 index)
    LEA.L	TM_BIT2_RESULT(PC),A6                 | set return address
    BRA.B	TM_DISPATCH_BY_INDEX                  | dispatch test 2
TM_BIT2_RESULT:
    TST.L	D6                                    | test 2 passed?
    BNE.W	TM_TEST_ERROR                         | failed: handle error
TM_BIT3_CHECK:
    BTST	#0xB,D7                                | test 3 selected? (bit 11)
    BEQ.B	TM_BIT4_CHECK                         | no: skip to test 4
    MOVEQ.L	#0x3,D1                             | D1 = 3 (test 3 index)
    LEA.L	TM_BIT3_RESULT(PC),A6                 | set return address
    BRA.B	TM_DISPATCH_BY_INDEX                  | dispatch test 3
TM_BIT3_RESULT:
    TST.L	D6                                    | test 3 passed?
    BNE.W	TM_TEST_ERROR                         | failed: handle error
TM_BIT4_CHECK:
    BTST	#0xC,D7                                | test 4 selected? (bit 12)
    BEQ.B	TM_BIT5_CHECK                         | no: skip to test 5
    MOVEQ.L	#0x4,D1                             | D1 = 4 (test 4 index)
    LEA.L	TM_BIT4_RESULT(PC),A6                 | set return address
    BRA.B	TM_DISPATCH_BY_INDEX                  | dispatch test 4
TM_BIT4_RESULT:
    TST.L	D6                                    | test 4 passed?
    BNE.W	TM_TEST_ERROR                         | failed: handle error
TM_BIT5_CHECK:
    BTST	#0xD,D7                                | test 5 selected? (bit 13)
    BEQ.B	TM_BIT6_CHECK                         | no: skip to test 6
    MOVEQ.L	#0x5,D1                             | D1 = 5 (test 5 index)
    LEA.L	TM_BIT5_RESULT(PC),A6                 | set return address
    BRA.B	TM_DISPATCH_BY_INDEX                  | dispatch test 5
TM_BIT5_RESULT:
    TST.L	D6                                    | test 5 passed?
    BNE.W	TM_TEST_ERROR                         | failed: handle error
TM_BIT6_CHECK:
    BTST	#0xE,D7                                | test 6 selected? (bit 14)
    BEQ.B	TM_BIT7_CHECK                         | no: skip to test 7
    MOVEQ.L	#0x6,D1                             | D1 = 6 (test 6 index)
    LEA.L	TM_BIT6_RESULT(PC),A6                 | set return address
    BRA.B	TM_DISPATCH_BY_INDEX                  | dispatch test 6
TM_BIT6_RESULT:
    TST.L	D6                                    | test 6 passed?
    BNE.W	TM_TEST_ERROR                         | failed: handle error
TM_BIT7_CHECK:
    BTST	#0xF,D7                                | test 7 selected? (bit 15)
    BEQ.B	TM_NEXT_ITER                          | no: all tests done
    MOVEQ.L	#0x7,D1                             | D1 = 7 (test 7 index)
    LEA.L	TM_BIT7_RESULT(PC),A6                 | set return address
    BRA.B	TM_DISPATCH_BY_INDEX                  | dispatch test 7
TM_BIT7_RESULT:
    TST.L	D6                                    | test 7 passed?
    BNE.B	TM_TEST_ERROR                         | failed: handle error
    BRA.B	TM_NEXT_ITER                          | all tests complete
| TM_DISPATCH_BY_INDEX - test dispatch: look up test D1 in TEST_DISPATCH_TBL and jump
| Called by: TM_SEL6_BITMASK_LOOP, TM_BIT1_CHECK, TM_BIT2_CHECK, TM_BIT3_CHECK, TM_BIT4_CHECK (and 3 more)
TM_DISPATCH_BY_INDEX:
    ASL.W	#0x1,D1                               | D1 *= 2 (word index into table)
    LEA.L	TEST_DISPATCH_TBL(PC),A5              | A5 = test dispatch table base
    MOVE.W	0x0(A5,D1.W),D1                      | D1 = PC-relative offset to test routine
    LEA.L	0x0(A5,D1.W),A5                       | A5 = test routine address
    JMP	(A5)                                    | jump to test routine
| TM_TEST_ERROR - test error handler: retry, loop, or continue
| Called by: TM_BIT0_RESULT, TM_BIT1_RESULT, TM_BIT2_RESULT, TM_BIT3_RESULT, TM_BIT4_RESULT (and 3 more)
TM_TEST_ERROR:
    BTST	#0x1D,D7                               | repeat-on-error? (bit 29)
    BEQ.B	TM_ERROR_CHK_LOOP                     | no: check loop-on-error
TM_ERROR_REPEAT_FOREVER:
    LEA.L	TM_ERROR_REPEAT_FOREVER(PC),A6        | set return to self (infinite retry)
    JMP	(A5)                                    | re-run failed test forever
TM_ERROR_CHK_LOOP:
    BTST	#0x1C,D7                               | loop-on-error? (bit 28)
    BNE.W	TM_TEST_COMPLETE                      | yes: skip to test-complete
| TM_NEXT_ITER - advance to next test in bit mask
TM_NEXT_ITER:
    SUBQ.B	#0x1,D7                              | decrement iteration count (low byte)
    BNE.W	TM_SEL6_BITMASK_LOOP                  | more iterations: re-scan bit mask
    BCLR	#0xF,D7                                | clear test 7 bit (was it last?)
    BNE.W	TM_SEL6_BITMASK_LOOP                  | was set: re-scan remaining tests
    BRA.W	TM_TEST_COMPLETE                      | all tests exhausted: to complete
| TESTMANAGER return paths
TM_RETURN:
    MOVE.W	(A7)+,SR                             | restore status register
TM_POP_AND_RETURN:
    MOVEM.L	(A7)+,D0-D7/A0-A6                   | restore all registers
    RTS                                         | return from TESTMANAGER
| Selector 2: return, discard saved SR (pop SR as data, not to SR)
TM_SEL2_RETURN_NO_SR:
    MOVE.W	(A7)+,D0                             | discard saved SR (pop to D0)
    BRA.B	TM_POP_AND_RETURN                     | restore regs and return
| Selector 3: reset state
TM_SEL3_RESET_STATE:
    MOVEQ.L	#0x0,D6                             | clear error accumulator
    MOVEQ.L	#0x0,D7                             | clear all flags
| TMRESTART - diagnostic test manager main loop
|
| Initializes SCC serial port, then enters an infinite loop reading
| commands via serial. Commands are single ASCII characters prefixed
| by '*'. The loop: init SCC -> read char -> parse command -> repeat.
TMRESTART:
    MOVE.W	#0x2700,SR                           | supervisor mode, IPL=7 (mask all interrupts)
    MOVEQ.L	#0x0,D5                             | clear D5 (received char / status)
    LEA.L	TMRESTART_SCC_INIT_DONE(PC),A6        | set return address for SCC init
    JMP	SCC_INIT(PC)                            | initialize SCC serial port
TMRESTART_SCC_INIT_DONE:
    LEA.L	TMRESTART_PARSE_CHAR(PC),A6           | set return address for char read
    JMP	SCC_RECV_CHAR(PC)                       | read character from SCC serial
| Command parser: D5 = received character
TMRESTART_PARSE_CHAR:
    TST.W	D5                                    | timeout/no data? (bit 15 = no char)
    BMI.W	TM_BEEP_CHECK                         | no char received: loop back
    ANDI.B	#0x7F,D5                             | strip parity bit (7-bit ASCII)
    CMPI.B	#0x2A,D5                             | received '*'? (command prefix)
    BNE.B	TMRESTART_CHK_PREFIX                  | no: check for command character
    BSET	#0x13,D7                               | set bit 19: command prefix received
    BRA.W	TM_BEEP_CHECK                         | wait for command character
TMRESTART_CHK_PREFIX:
    BTST	#0x13,D7                               | command prefix active? (bit 19)
    BEQ.W	TM_CMD_UNKNOWN                        | no prefix: echo char and loop
    BCLR	#0x13,D7                               | clear prefix flag (consume it)
| Command '*S' (0x53) - Start: disable timer beep, begin test sequence
    CMPI.B	#0x53,D5                             | command = 'S'?
    BNE.B	TM_CMD_TRY_L                          | no: try next command
    BCLR	#0x10,D7                               | clear bit 16: disable timer beep
    BCLR	#0x16,D7                               | clear bit 22: disable beep auto-reload
    BRA.W	TM_PROMPT                             | prompt and loop
| Command '*L' (0x4C) - Load address: read 8 hex digits into A4
TM_CMD_TRY_L:
    CMPI.B	#0x4C,D5                             | command = 'L'?
    BNE.B	TM_CMD_TRY_B                          | no: try next command
    MOVEQ.L	#0x4,D2                             | D2 = 4 bytes (8 hex digits)
    LEA.L	TM_CMD_L_ECHO(PC),A6                  | set return address
    JMP	TM_HEX_READ(PC)                         | read hex value from serial
TM_CMD_L_ECHO:
    MOVEA.L	D1,A4                               | A4 = load address from hex input
    BTST	#0x15,D7                               | echo enabled? (bit 21)
    BEQ.W	TM_PROMPT                             | no: prompt and loop
    BCLR	#0x17,D7                               | clear CR/LF flag for echo
    MOVE.L	D1,D0                                | D0 = address to echo
    MOVEQ.L	#0x4,D2                             | D2 = 4 bytes to print
    LEA.L	TM_PROMPT(PC),A6                      | return to prompt after echo
    JMP	TM_HEX_PRINT(PC)                        | print hex value to serial
| Command '*B' (0x42) - Byte count: read 4 hex digits into D4
TM_CMD_TRY_B:
    CMPI.B	#0x42,D5                             | command = 'B'?
    BNE.B	TM_CMD_TRY_D                          | no: try next command
    MOVEQ.L	#0x2,D2                             | D2 = 2 bytes (4 hex digits)
    LEA.L	TM_CMD_B_ECHO(PC),A6                  | set return address
    JMP	TM_HEX_READ(PC)                         | read hex value from serial
TM_CMD_B_ECHO:
    MOVE.W	D1,D4                                | D4 = byte count from hex input
    BTST	#0x15,D7                               | echo enabled? (bit 21)
    BEQ.W	TM_PROMPT                             | no: prompt and loop
    BCLR	#0x17,D7                               | clear CR/LF flag for echo
    MOVE.L	D1,D0                                | D0 = count to echo
    MOVEQ.L	#0x2,D2                             | D2 = 2 bytes to print
    LEA.L	TM_PROMPT(PC),A6                      | return to prompt after echo
    JMP	TM_HEX_PRINT(PC)                        | print hex value to serial
| Command '*D' (0x44) - Data: read D4 bytes into memory at (A4)+
TM_CMD_TRY_D:
    CMPI.B	#0x44,D5                             | command = 'D'?
    BNE.B	TM_CMD_TRY_C                          | no: try next command
    MOVEQ.L	#0x0,D3                             | D3 = 0 (running checksum accumulator)
    SUBQ.W	#0x1,D4                              | adjust count for DBF loop
    BGE.B	TM_CMD_D_BYTELOOP                     | count > 0: proceed
    CLR.W	D4                                    | ensure non-negative count
TM_CMD_D_BYTELOOP:
    MOVE.W	#0x1,D2                              | D2 = 1 byte (2 hex digits per byte)
    LEA.L	TM_CMD_D_STORE(PC),A6                 | set return address
    JMP	TM_HEX_READ(PC)                         | read hex byte from serial
TM_CMD_D_STORE:
    MOVE.B	D1,(A4)+                             | store received byte at load address
    MOVEQ.L	#0x0,D0                             | clear D0 high bytes
    MOVE.B	D1,D0                                | D0 = byte value
    ADD.L	D0,D3                                 | accumulate byte checksum
    DBF.W	D4,TM_CMD_D_BYTELOOP                  | loop for remaining bytes
    BRA.W	TM_PROMPT                             | all bytes received: prompt
| Command '*C' (0x43) - Checksum: compare expected vs accumulated
TM_CMD_TRY_C:
    CMPI.B	#0x43,D5                             | command = 'C'?
    BNE.B	TM_CMD_TRY_G                          | no: try next command
    MOVEQ.L	#0x4,D2                             | D2 = 4 bytes (expected checksum)
    LEA.L	TM_CMD_C_COMPARE(PC),A6               | set return address
    JMP	TM_HEX_READ(PC)                         | read expected checksum from serial
TM_CMD_C_COMPARE:
    SWAP.W	D5                                   | save current char in D5 high
    MOVE.B	#0x47,D5                             | D5 high = 'G' (good, assume match)
    SWAP.W	D5                                   | restore D5
    CMP.L	D1,D3                                 | accumulated == expected?
    BEQ.W	TM_PROMPT                             | match: report 'G' and loop
    SWAP.W	D5                                   | mismatch: change result
    MOVE.B	#0x4E,D5                             | D5 high = 'N' (no good)
    SWAP.W	D5                                   | restore D5
    BRA.W	TM_PROMPT                             | report 'N' and loop
| Command '*G' (0x47) - Go: read address, echo "*G", jump to address
TM_CMD_TRY_G:
    CMPI.B	#0x47,D5                             | command = 'G'?
    BNE.B	TM_CMD_TRY_0                          | no: try next command
    MOVEQ.L	#0x4,D2                             | D2 = 4 bytes (target address)
    LEA.L	TM_CMD_G_ECHO_STAR(PC),A6             | set return address
    JMP	TM_HEX_READ(PC)                         | read target address from serial
TM_CMD_G_ECHO_STAR:
    MOVEA.L	D1,A3                               | A3 = jump target address
    MOVE.B	#0x2A,D0                             | D0 = '*' (echo command prefix)
    LEA.L	TM_CMD_G_ECHO_G(PC),A6                | set return address
    JMP	SCC_SEND_CHAR(PC)                       | send '*' to serial
TM_CMD_G_ECHO_G:
    MOVE.B	#0x47,D0                             | D0 = 'G' (echo command name)
    LEA.L	TM_CMD_G_ECHO_CRLF(PC),A6             | set return address
    JMP	SCC_SEND_CHAR(PC)                       | send 'G' to serial
TM_CMD_G_ECHO_CRLF:
    BSET	#0x17,D7                               | set CR/LF flag for newline after echo
    MOVEQ.L	#0x0,D2                             | D2 = 0 (no hex digits to print)
    LEA.L	TM_CMD_G_JUMP(PC),A6                  | set return address
    JMP	TM_HEX_PRINT(PC)                        | print CR/LF
TM_CMD_G_JUMP:
    BCLR	#0x17,D7                               | clear CR/LF flag
    LEA.L	TM_PROMPT(PC),A6                      | set return to prompt loop
    JMP	(A3)                                    | jump to target address
| Command '*0' (0x30) - set A0 (test start address)
TM_CMD_TRY_0:
    CMPI.B	#0x30,D5                             | command = '0'?
    BNE.B	TM_CMD_TRY_1                          | no: try next command
    MOVEQ.L	#0x4,D2                             | D2 = 4 bytes (address)
    LEA.L	TM_CMD_0_ECHO(PC),A6                  | set return address
    JMP	TM_HEX_READ(PC)                         | read hex address from serial
TM_CMD_0_ECHO:
    MOVEA.L	D1,A0                               | A0 = start address from hex input
    BTST	#0x15,D7                               | echo enabled? (bit 21)
    BEQ.W	TM_PROMPT                             | no: prompt and loop
    BCLR	#0x17,D7                               | clear CR/LF flag for echo
    MOVE.L	D1,D0                                | D0 = address to echo
    MOVEQ.L	#0x4,D2                             | D2 = 4 bytes to print
    LEA.L	TM_PROMPT(PC),A6                      | return to prompt after echo
    JMP	TM_HEX_PRINT(PC)                        | print hex value to serial
| Command '*1' (0x31) - set A1 (test end address)
TM_CMD_TRY_1:
    CMPI.B	#0x31,D5                             | command = '1'?
    BNE.B	TM_CMD_TRY_2                          | no: try next command
    MOVEQ.L	#0x4,D2                             | D2 = 4 bytes (address)
    LEA.L	TM_CMD_1_ECHO(PC),A6                  | set return address
    JMP	TM_HEX_READ(PC)                         | read hex address from serial
TM_CMD_1_ECHO:
    MOVEA.L	D1,A1                               | A1 = end address from hex input
    BTST	#0x15,D7                               | echo enabled? (bit 21)
    BEQ.W	TM_PROMPT                             | no: prompt and loop
    BCLR	#0x17,D7                               | clear CR/LF flag for echo
    MOVE.L	D1,D0                                | D0 = address to echo
    MOVEQ.L	#0x4,D2                             | D2 = 4 bytes to print
    LEA.L	TM_PROMPT(PC),A6                      | return to prompt after echo
    JMP	TM_HEX_PRINT(PC)                        | print hex value to serial
| Command '*2' (0x32) - reserved (no-op)
TM_CMD_TRY_2:
    CMPI.B	#0x32,D5                             | command = '2'?
    BNE.B	TM_CMD_TRY_3                          | no: try next command
    BRA.W	TM_PROMPT                             | no-op: prompt and loop
| Command '*3' (0x33) - reserved (no-op)
TM_CMD_TRY_3:
    CMPI.B	#0x33,D5                             | command = '3'?
    BNE.B	TM_CMD_TRY_4                          | no: try next command
    BRA.W	TM_PROMPT                             | no-op: prompt and loop
| Command '*4' (0x34) - Reset: clear all state
TM_CMD_TRY_4:
    CMPI.B	#0x34,D5                             | command = '4'?
    BNE.B	TM_CMD_TRY_5                          | no: try next command
    CLR.W	D7                                    | clear low flags (test phase/select)
    MOVEQ.L	#0x0,D6                             | clear error accumulator
    BRA.W	TM_PROMPT                             | prompt and loop
| Command '*5' (0x35) - enable timer beep with auto-reload
TM_CMD_TRY_5:
    CMPI.B	#0x35,D5                             | command = '5'?
    BNE.B	TM_CMD_TRY_A                          | no: try next command
    BSET	#0x16,D7                               | set bit 22: timer beep auto-reload
    BSET	#0x10,D7                               | set bit 16: enable timer beep
    MOVE.W	#0xC,D4                              | D4 low = 12 (timer reload count)
    SWAP.W	D4                                   | move to high word for countdown
    LEA.L	TM_PROMPT(PC),A6                      | return to prompt after init
    JMP	VIA_T1_INIT_BEEP(PC)                    | init VIA Timer 1 for beep
| Command '*A' (0x41) - enable hex digit display mode
TM_CMD_TRY_A:
    CMPI.B	#0x41,D5                             | command = 'A'?
    BNE.B	TM_CMD_TRY_H                          | no: try next command
    BSET	#0x14,D7                               | set bit 20: hex digit mode (nibbles)
    BRA.W	TM_PROMPT                             | prompt and loop
| Command '*H' (0x48) - disable hex digit display mode
TM_CMD_TRY_H:
    CMPI.B	#0x48,D5                             | command = 'H'?
    BNE.B	TM_CMD_TRY_R                          | no: try next command
    BCLR	#0x14,D7                               | clear bit 20: byte mode (not nibbles)
    BRA.W	TM_PROMPT                             | prompt and loop
| Command '*R' (0x52) - Report: print D6 (error) and D7 (flags)
TM_CMD_TRY_R:
    CMPI.B	#0x52,D5                             | command = 'R'?
    BNE.B	TM_CMD_TRY_M                          | no: try next command
    BCLR	#0x17,D7                               | clear CR/LF flag
    MOVE.L	D6,D0                                | D0 = error accumulator
    MOVEQ.L	#0x4,D2                             | D2 = 4 bytes (print 8 hex digits)
    LEA.L	TM_CMD_R_PRINT_FLAGS(PC),A6           | set return address
    JMP	TM_HEX_PRINT(PC)                        | print D6 as hex to serial
TM_CMD_R_PRINT_FLAGS:
    BCLR	#0x17,D7                               | clear CR/LF flag
    MOVE.W	D7,D0                                | D0 = flags low word
    MOVEQ.L	#0x2,D2                             | D2 = 2 bytes (print 4 hex digits)
    LEA.L	TM_PROMPT(PC),A6                      | return to prompt after print
    JMP	TM_HEX_PRINT(PC)                        | print D7 flags as hex to serial
| Command '*M' (0x4D) - Memory dump: print longwords from (A4)
TM_CMD_TRY_M:
    CMPI.B	#0x4D,D5                             | command = 'M'?
    BNE.B	TM_CMD_TRY_E                          | no: try next command
    ASR.W	#0x2,D4                               | D4 = byte count / 4 (longword count)
    SUBQ.W	#0x1,D4                              | adjust for DBF loop
    BGE.B	TM_CMD_M_PRELOOP                      | count > 0: proceed
    CLR.W	D4                                    | ensure non-negative
TM_CMD_M_PRELOOP:
    BSET	#0x17,D7                               | set CR/LF flag (newline per longword)
TM_CMD_M_LOOP:
    MOVE.L	(A4)+,D0                             | D0 = next longword from memory
    LEA.L	TM_CMD_M_NEXT(PC),A6                  | set return address
    MOVEQ.L	#0x4,D2                             | D2 = 4 bytes to print
    JMP	TM_HEX_PRINT(PC)                        | print longword as hex to serial
TM_CMD_M_NEXT:
    DBF.W	D4,TM_CMD_M_LOOP                      | loop for remaining longwords
    BRA.W	TM_PROMPT                             | done: prompt and loop
| Command '*E' (0x45) - Echo: enable serial echo mode
TM_CMD_TRY_E:
    CMPI.B	#0x45,D5                             | command = 'E'?
    BNE.B	TM_CMD_TRY_I                          | no: try next command
    BSET	#0x15,D7                               | set bit 21: serial echo enabled
    BRA.W	TM_PROMPT                             | prompt and loop
| Command '*I' (0x49) - Init: full cold restart
TM_CMD_TRY_I:
    CMPI.B	#0x49,D5                             | command = 'I'?
    BNE.B	TM_CMD_TRY_T                          | no: try next command
    JMP	STARTTEST1(PC)                          | restart from cold boot entry
| Command '*T' (0x54) - Test: read test params and run test by number
| Reads 8 hex digits for test address, then 4 hex digits for flags.
| Flags are shifted into D7 bits 28-31, then dispatches via TEST_DISPATCH_TBL.
| Uses USP to save the test address across the dispatch sequence.
TM_CMD_TRY_T:
    CMPI.B	#0x54,D5                             | command = 'T'?
    BNE.W	TM_CMD_UNKNOWN                        | no: unknown, echo and loop
    MOVEQ.L	#0x4,D2                             | D2 = 4 bytes (test address)
    LEA.L	TM_CMD_T_GOT_ADDR(PC),A6              | set return address
    JMP	TM_HEX_READ(PC)                         | read test address from serial
TM_CMD_T_GOT_ADDR:
    MOVEA.L	D1,A0                               | A0 = test address
    MOVE.L	A0,USP                               | save test address in USP
    MOVEQ.L	#0x2,D2                             | D2 = 2 bytes (control flags)
    LEA.L	TM_CMD_T_GOT_FLAGS(PC),A6             | set return address
    JMP	TM_HEX_READ(PC)                         | read control flags from serial
TM_CMD_T_GOT_FLAGS:
    MOVE.W	D1,D4                                | D4 = save flags for iteration count
    MOVE.W	#0x1C,D2                             | D2 = 28 (shift count)
    LSL.L	D2,D1                                 | shift flags to bits 28-31
    OR.L	D1,D7                                  | merge into D7 control bits
    BTST	#0x15,D7                               | echo enabled? (bit 21)
    BEQ.B	TM_CMD_T_RUN                          | no: skip echo, begin test
    MOVE.L	USP,A0                               | A0 = test address from USP
    MOVE.L	A0,D0                                | D0 = address to echo
    MOVEQ.L	#0x4,D2                             | D2 = 4 bytes to print
    LEA.L	TM_CMD_T_ECHO_FLAGS(PC),A6            | set return address
    JMP	TM_HEX_PRINT(PC)                        | echo test address to serial
TM_CMD_T_ECHO_FLAGS:
    MOVE.W	D4,D0                                | D0 = control flags to echo
    MOVEQ.L	#0x2,D2                             | D2 = 2 bytes to print
    LEA.L	TM_CMD_T_RUN(PC),A6                   | set return address
    JMP	TM_HEX_PRINT(PC)                        | echo control flags to serial
| '*T' test execution: dispatch test and iterate
TM_CMD_T_RUN:
    MOVEQ.L	#0x0,D6                             | clear error accumulator for test run
    MOVE.L	USP,A0                               | A0 = test address (from USP)
    MOVE.L	A0,D1                                | D1 = test address
    SWAP.W	D1                                   | D1 = high word (test number)
    MOVE.B	#0x3F,D5                             | D5 = '?' (will be status after run)
    CMP.W	TEST_TABLE_COUNT(PC),D1               | test number within table bounds?
    BGE.B	TM_CMD_UNKNOWN                        | out of range: unknown command
    ASL.W	#0x1,D1                               | D1 *= 2 (word index)
    LEA.L	TEST_DISPATCH_TBL(PC),A5              | A5 = test dispatch table base
    MOVE.W	0x0(A5,D1.W),D1                      | D1 = offset to test routine
    LEA.L	0x0(A5,D1.W),A5                       | A5 = test routine address
    LEA.L	TM_CMD_T_RESULT(PC),A6                | set return address
    JMP	(A5)                                    | call test routine
TM_CMD_T_RESULT:
    TST.L	D6                                    | test passed? (D6 = 0)
    BEQ.B	TM_CMD_T_DEC_ITER                     | pass: continue iterations
    BTST	#0x1D,D7                               | repeat-on-error? (bit 29)
    BEQ.B	TM_CMD_T_CHK_LOOP_ON_ERR              | no: check loop-on-error
TM_CMD_T_REPEAT_FOREVER:
    LEA.L	TM_CMD_T_REPEAT_FOREVER(PC),A6        | set return to self (retry forever)
    JMP	(A5)                                    | re-run failed test
TM_CMD_T_CHK_LOOP_ON_ERR:
    BTST	#0x1C,D7                               | loop-on-error? (bit 28)
    BNE.B	TM_CMD_T_DONE                         | yes: finish with 'T' status
| Test passed or no error flags: decrement iteration counter
TM_CMD_T_DEC_ITER:
    MOVE.L	USP,A0                               | A0 = iteration count (stored in USP)
    MOVE.L	A0,D1                                | D1 = count
    SUBQ.W	#0x1,D1                              | decrement iteration count
    MOVEA.L	D1,A0                               | save back
    MOVE.L	A0,USP                               | store decremented count in USP
    TST.W	D1                                    | iterations exhausted?
    BEQ.B	TM_CMD_T_DONE                         | yes: finish with 'T' status
    LEA.L	TM_CMD_T_CHK_ABORT(PC),A6             | set return address
    JMP	SCC_RECV_CHAR(PC)                       | check for abort key (serial input)
TM_CMD_T_CHK_ABORT:
    TST.W	D5                                    | key pressed? (abort check)
    BMI.B	TM_CMD_T_RUN                          | no key: continue test iterations
| '*T' complete: set status to 'T' and return to prompt
TM_CMD_T_DONE:
    MOVE.L	#0x540054,D5                         | D5 = 'T','T' (status = test complete)
    BRA.B	TM_PROMPT                             | prompt and loop
| Unknown command: echo the received character
TM_CMD_UNKNOWN:
    CLR.W	D0                                    | clear D0 high byte
    MOVE.B	D5,D0                                | D0 = received character
    LEA.L	TM_PROMPT_DONE(PC),A6                 | set return address
    JMP	SCC_SEND_CHAR(PC)                       | echo character to serial
| TM_PROMPT - command prompt: send "*<status>" with CR/LF, then loop
| Called by: TM_CMD_C_COMPARE, TMRESTART_CHK_PREFIX, TM_CMD_L_ECHO, TM_CMD_B_ECHO, TM_CMD_D_STORE (and 10 more)
TM_PROMPT:
    MOVE.B	#0x2A,D0                             | D0 = '*' (prompt character)
    LEA.L	TM_PROMPT_STATUS(PC),A6               | set return address
    JMP	SCC_SEND_CHAR(PC)                       | send '*' to serial
TM_PROMPT_STATUS:
    SWAP.W	D5                                   | get status byte from D5 high
    MOVE.B	D5,D0                                | D0 = status character
    SWAP.W	D5                                   | restore D5
    LEA.L	TM_PROMPT_CRLF(PC),A6                 | set return address
    JMP	SCC_SEND_CHAR(PC)                       | send status char to serial
TM_PROMPT_CRLF:
    BSET	#0x17,D7                               | set CR/LF flag (newline after prompt)
    MOVEQ.L	#0x0,D2                             | D2 = 0 (no hex digits)
    LEA.L	TM_PROMPT_DONE(PC),A6                 | set return address
    JMP	TM_HEX_PRINT(PC)                        | print CR/LF via hex printer
TM_PROMPT_DONE:
    BCLR	#0x17,D7                               | clear CR/LF flag
| TM_BEEP_CHECK - timer beep check: if beep enabled, check timer and
| optionally send status string before looping back to read next char.
TM_BEEP_CHECK:
    BTST	#0x10,D7                               | timer beep enabled? (bit 16)
    BEQ.B	TM_LOOP_NEXT_CHAR                     | no: loop back to read char
    BTST	#0x16,D7                               | auto-reload? (bit 22)
    BEQ.B	TM_BEEP_SEND_STATUS                   | no: skip reload check
    MOVE.W	#0xC,D0                              | D0 = 12 (reload count)
    LEA.L	TM_BEEP_TIMER_CHECK(PC),A6            | set return address
    JMP	VIA_T1_CHECK_RELOAD(PC)                 | check/reload VIA Timer 1
TM_BEEP_TIMER_CHECK:
    TST.W	D0                                    | timer expired? (D0.bit15 set)
    BPL.B	TM_LOOP_NEXT_CHAR                     | no: loop back to read char
| Timer expired: send status string " *APPLE*" + D6 + D7 + "2*\r\n"
TM_BEEP_SEND_STATUS:
    LEA.L	TM_BEEP_PREFIX_STR(PC),A1             | A1 = prefix string data
    CLR.W	D4                                    | clear counter high byte
    MOVE.B	(A1)+,D4                             | D4 = string length - 1
TM_BEEP_PREFIX_LOOP:
    MOVE.B	(A1)+,D0                             | D0 = next char to send
    LEA.L	TM_BEEP_PREFIX_NEXT(PC),A6            | set return address
    JMP	SCC_SEND_CHAR(PC)                       | send char to serial
TM_BEEP_PREFIX_NEXT:
    DBF.W	D4,TM_BEEP_PREFIX_LOOP                | loop for all prefix chars
    BCLR	#0x17,D7                               | clear CR/LF (inline status)
    BSET	#0x14,D7                               | set hex digit mode for status
    MOVE.L	D6,D0                                | D0 = error accumulator
    MOVEQ.L	#0x4,D2                             | D2 = 4 bytes (8 hex nibbles)
    LEA.L	TM_BEEP_PRINT_D7(PC),A6               | set return address
    JMP	TM_HEX_PRINT(PC)                        | print D6 as hex
TM_BEEP_PRINT_D7:
    MOVE.W	D7,D0                                | D0 = flags low word
    MOVEQ.L	#0x2,D2                             | D2 = 2 bytes (4 hex nibbles)
    LEA.L	TM_BEEP_SUFFIX_INIT(PC),A6            | set return address
    JMP	TM_HEX_PRINT(PC)                        | print D7 flags as hex
TM_BEEP_SUFFIX_INIT:
    BCLR	#0x14,D7                               | restore byte mode
    LEA.L	TM_BEEP_SUFFIX_STR(PC),A1             | A1 = suffix string data
    CLR.W	D4                                    | clear counter high byte
    MOVE.B	(A1)+,D4                             | D4 = string length - 1
TM_BEEP_SUFFIX_LOOP:
    MOVE.B	(A1)+,D0                             | D0 = next char to send
    LEA.L	TM_BEEP_SUFFIX_NEXT(PC),A6            | set return address
    JMP	SCC_SEND_CHAR(PC)                       | send char to serial
TM_BEEP_SUFFIX_NEXT:
    DBF.W	D4,TM_BEEP_SUFFIX_LOOP                | loop for all suffix chars
    BTST	#0x16,D7                               | auto-reload active? (bit 22)
    BNE.B	TM_LOOP_NEXT_CHAR                     | yes: keep beep enabled
    BCLR	#0x10,D7                               | no: disable beep (one-shot)
TM_LOOP_NEXT_CHAR:
    BRA.W	TMRESTART_SCC_INIT_DONE               | loop: read next serial char
| TM_BEEP_PREFIX_STR - timer status prefix: " *APPLE*"
TM_BEEP_PREFIX_STR:
    .short	0x062A                               | count=6, '*'
    .long	0x4150504C
    .short	0x452A
| TM_BEEP_SUFFIX_STR - timer status suffix: "2*\r\n"
TM_BEEP_SUFFIX_STR:
    .short	0x042A                               | count=4, '*'
    .long	0x322A0D0A                            | '2*' CR LF
| SCC_RECV_CHAR - read one character from SCC serial port (channel B)
|
| Entry: D7 bit 17 = SCC initialized
| Exit: D5 = received character (bit 15 set if no data available)
|       D5 high word = char saved for command prefix tracking
SCC_RECV_CHAR:
    MOVE.W	#0x8000,D5                           | D5 = 0x8000 (no-data sentinel)
    BTST	#0x11,D7                               | SCC initialized? (bit 17)
    BEQ.B	SCC_RECV_NO_DATA                      | no: return no-data
    LEA.L	(SCCRd_Base).L,A2                     | A2 = SCC read base
    BTST	#0x0,0x2(A2)                           | RR0 bit 0: Rx char available?
    BEQ.B	SCC_RECV_NO_DATA                      | no char available: return
    MOVE.B	#0x1,D0                              | select SCC register 1
    LEA.L	(SCCWr_Base).L,A2                     | A2 = SCC write base
    MOVE.B	D0,0x2(A2)                           | write WR0: point to RR1
    LEA.L	(SCCRd_Base).L,A2                     | A2 = SCC read base
    MOVE.B	0x2(A2),D0                           | D0 = RR1 (error status)
    ANDI.B	#0x70,D0                             | mask error bits (parity/overrun/framing)
    BEQ.B	SCC_RECV_STORE                        | no errors: proceed to read data
    LEA.L	(SCCWr_Base).L,A2                     | A2 = SCC write base
    MOVE.B	#0x30,0x2(A2)                        | WR0 cmd: error reset
SCC_RECV_STORE:
    BCLR	#0xF,D5                                | clear no-data sentinel (char received)
    LSL.L	#0x8,D0                               | shift error status to high byte
    OR.W	D0,D5                                  | merge error status into D5
    LEA.L	(SCCRd_Base).L,A2                     | A2 = SCC read base
    MOVE.B	0x6(A2),D5                           | D5 low = received data byte (RR8)
    BTST	#0x13,D7                               | command prefix active? (bit 19)
    BEQ.B	SCC_RECV_DONE                         | no: return char as-is
    MOVE.B	D5,D0                                | save char in D0
    SWAP.W	D5                                   | save char to D5 high word
    MOVE.B	D0,D5                                | also keep in D5 low for parsing
    SWAP.W	D5                                   | restore D5 (high = saved char)
SCC_RECV_DONE:
    JMP	(A6)                                    | tail-call return from SCC_RECV_DONE via A6
| SCC_RECV_NO_DATA - no SCC data: check alternate polling, return no-data
SCC_RECV_NO_DATA:
    BTST	#0x12,D7                               | alternate polling mode? (bit 18)
    BEQ.B	SCC_RECV_RETURN                       | no: return immediately
    NOP                                         | timing delay for alternate poll
    NOP                                         | timing delay
SCC_RECV_RETURN:
    JMP	(A6)                                    | return with D5 = no-data sentinel
| TM_HEX_DIGIT - parse ASCII hex digit to binary nibble
|
| Entry: D0 = ASCII character
| Exit: D0 = 0-15 (valid hex digit) or 0 (invalid)
TM_HEX_DIGIT:
    ANDI.W	#0x7F,D0                             | strip parity (7-bit ASCII)
    SUBI.B	#0x30,D0                             | subtract '0' (ASCII 0x30)
    BMI.B	TM_HEX_DIGIT_BAD                      | < '0': invalid
    CMPI.B	#0x16,D0                             | > 'F' (0x46 - 0x30 = 0x16)?
    BGT.B	TM_HEX_DIGIT_BAD                      | invalid: too high
    CMPI.B	#0x9,D0                              | <= 9? (decimal digit)
    BLE.B	TM_HEX_DIGIT_OK                       | yes: digit is ready (0-9)
    SUBQ.B	#0x7,D0                              | adjust A-F: subtract gap (10='A'-7)
TM_HEX_DIGIT_OK:
    JMP	(A6)                                    | return with D0 = binary nibble
TM_HEX_DIGIT_BAD:
    CLR.W	D0                                    | invalid digit: return 0
    JMP	(A6)                                    | tail-call return from TM_HEX_DIGIT_BAD via A6
| TM_HEX_READ - read hex value from serial port
|
| Reads D2 bytes (D2*2 hex digits) from serial. In hex-digit mode
| (bit 20), reads D2*2 nibbles. Accumulates into D1.
| Entry: D2 = byte count, A6 = return address (saved to A5)
| Exit: D1 = parsed hex value
| Called by: TM_CMD_TRY_L, TM_CMD_TRY_B, TM_CMD_D_BYTELOOP, TM_CMD_TRY_C, TM_CMD_TRY_G (and 4 more)
TM_HEX_READ:
    MOVEA.L	A6,A5                               | A5 = save return address
    MOVEQ.L	#0x0,D1                             | D1 = 0 (accumulator)
    BTST	#0x14,D7                               | hex digit mode? (bit 20)
    BEQ.B	TM_HEX_READ_LOOP_INIT                 | no: byte mode
    ASL.W	#0x1,D2                               | D2 *= 2 (nibble count in digit mode)
TM_HEX_READ_LOOP_INIT:
    SUBQ.W	#0x1,D2                              | adjust for DBF loop
TM_HEX_READ_LOOP:
    LEA.L	TM_HEX_READ_GOT_CHAR(PC),A6           | set return address
    JMP	SCC_RECV_CHAR(PC)                       | read char from SCC serial
TM_HEX_READ_GOT_CHAR:
    TST.W	D5                                    | char received? (bit 15 clear)
    BMI.B	TM_HEX_READ_LOOP                      | no: keep polling
    MOVE.B	D5,D0                                | D0 = received character
    BTST	#0x14,D7                               | hex digit mode? (bit 20)
    BEQ.B	TM_HEX_READ_BYTE                      | no: accumulate raw byte
    LEA.L	TM_HEX_READ_NIBBLE(PC),A6             | set return address
    JMP	TM_HEX_DIGIT(PC)                        | parse hex digit to nibble
TM_HEX_READ_NIBBLE:
    LSL.L	#0x4,D1                               | shift accumulator left by 4 bits
    OR.B	D0,D1                                  | merge nibble into accumulator
    BRA.B	TM_HEX_READ_NEXT                      | continue loop
TM_HEX_READ_BYTE:
    LSL.L	#0x8,D1                               | shift accumulator left by 8 bits
    MOVE.B	D0,D1                                | merge raw byte into accumulator
TM_HEX_READ_NEXT:
    DBF.W	D2,TM_HEX_READ_LOOP                   | loop for remaining digits/bytes
    JMP	(A5)                                    | return to caller (D1 = result)
| TM_HEX_PRINT - print hex value to SCC serial port
|
| Prints D0 as hex (D2 bytes). In hex-digit mode (bit 20), prints
| nibbles with ASCII hex conversion. In byte mode, sends raw bytes.
| If CR/LF flag (bit 23) is set, appends CR LF after the value.
| Entry: D0 = value, D2 = byte count, A6 = return address (saved to A5)
| Called by: TM_CMD_L_ECHO, TM_CMD_B_ECHO, TM_CMD_G_ECHO_CRLF, TM_CMD_0_ECHO, TM_CMD_1_ECHO (and 8 more)
TM_HEX_PRINT:
    MOVEA.L	A6,A5                               | A5 = save return address
    MOVE.L	D0,D3                                | D3 = value to print
    TST.W	D2                                    | byte count = 0?
    BEQ.B	TM_HEX_PRINT_CHK_CRLF                 | yes: skip to CR/LF check
    MOVE.W	D2,D1                                | D1 = byte count
    MOVEQ.L	#0x4,D0                             | D0 = 4 (max bytes)
    SUB.W	D1,D0                                 | D0 = 4 - count
    NEG.W	D0                                    | D0 = count - 4
    MULU.W	#0x8,D0                              | D0 = bit shift to left-align
    ROL.L	D0,D3                                 | left-align value for extraction
    MOVEQ.L	#0x0,D0                             | clear D0
    BTST	#0x14,D7                               | hex digit mode? (bit 20)
    BEQ.B	TM_HEX_PRINT_LOOP_INIT                | no: byte mode
    ASL.W	#0x1,D2                               | D2 *= 2 (nibble count)
TM_HEX_PRINT_LOOP_INIT:
    SUBQ.W	#0x1,D2                              | adjust for DBF loop
TM_HEX_PRINT_LOOP:
    BTST	#0x14,D7                               | hex digit mode? (bit 20)
    BNE.B	TM_HEX_PRINT_NIBBLE                   | yes: extract nibble
    ROL.L	#0x8,D3                               | rotate next byte to low position
    MOVE.B	D3,D0                                | D0 = raw byte to send
    BRA.B	TM_HEX_PRINT_SEND                     | send it
TM_HEX_PRINT_NIBBLE:
    ROL.L	#0x4,D3                               | rotate next nibble to low position
    MOVE.B	D3,D0                                | D0 = nibble (may have high bits)
    ANDI.B	#0xF,D0                              | mask to 4 bits (0-15)
    CMPI.B	#0xA,D0                              | >= 10? (A-F)
    BLT.B	TM_HEX_PRINT_DIGIT                    | no: digit 0-9
    ADDQ.B	#0x7,D0                              | adjust for 'A'-'F' (add 7)
TM_HEX_PRINT_DIGIT:
    ADDI.B	#0x30,D0                             | convert to ASCII ('0' = 0x30)
TM_HEX_PRINT_SEND:
    LEA.L	TM_HEX_PRINT_NEXT(PC),A6              | set return address
    JMP	SCC_SEND_CHAR(PC)                       | send character to serial
TM_HEX_PRINT_NEXT:
    DBF.W	D2,TM_HEX_PRINT_LOOP                  | loop for remaining chars
TM_HEX_PRINT_CHK_CRLF:
    BTST	#0x17,D7                               | CR/LF flag set? (bit 23)
    BEQ.B	TM_HEX_PRINT_DONE                     | no: return
    MOVE.B	#0xD,D0                              | D0 = CR (carriage return)
    LEA.L	TM_HEX_PRINT_LF(PC),A6                | set return address
    JMP	SCC_SEND_CHAR(PC)                       | send CR to serial
TM_HEX_PRINT_LF:
    MOVE.B	#0xA,D0                              | D0 = LF (line feed)
    LEA.L	TM_HEX_PRINT_DONE(PC),A6              | set return address
    JMP	SCC_SEND_CHAR(PC)                       | send LF to serial
TM_HEX_PRINT_DONE:
    JMP	(A5)                                    | tail-call return from TM_HEX_PRINT_DONE via A5
| SCC_SEND_CHAR - write one character to SCC serial port (channel B)
|
| Entry: D0 = character to send
| Waits for TX buffer ready before returning.
| Called by: TM_CMD_G_ECHO_STAR, TM_CMD_G_ECHO_G, TM_CMD_UNKNOWN, TM_PROMPT, TM_PROMPT_STATUS (and 5 more)
SCC_SEND_CHAR:
    LEA.L	(SCCWr_Base).L,A2                     | A2 = SCC write base
    MOVE.B	#0x30,0x2(A2)                        | WR0 cmd: error reset (pre-clear)
    MOVE.B	D0,0x6(A2)                           | WR8: write TX data byte
SCC_SEND_WAIT:
    LEA.L	(SCCWr_Base).L,A2                     | A2 = SCC write base
    MOVE.W	#0x1,D0                              | select register 1
    MOVE.B	D0,0x2(A2)                           | WR0: point to RR1
    LEA.L	(SCCRd_Base).L,A2                     | A2 = SCC read base
    BTST	#0x0,0x2(A2)                           | RR0 bit 0: TX buffer empty?
    BEQ.B	SCC_SEND_WAIT                         | not yet: keep polling
    JMP	(A6)                                    | TX complete: return
| SCC_INIT - initialize SCC serial port (channel B, modem port)
|
| Programs SCC channel B registers from SCC_INIT_REGS table for
| 9600 baud, 8N1 serial communication. Flushes receive buffer,
| enables sound output via VIA port B, marks SCC as initialized.
SCC_INIT:
    LEA.L	(SCCWr_Base).L,A0                     | A0 = SCC write base
    TST.B	(A0)                                  | read to reset SCC pointer
    LEA.L	SCC_INIT_REGS(PC),A1                  | A1 = SCC init register table
SCC_INIT_LOOP:
    MOVE.B	(A1)+,D0                             | D0 = register number
    BMI.B	SCC_INIT_FLUSH                        | negative: end of table
    MOVE.B	D0,0x2(A0)                           | WR0: select register
    MOVE.B	(A1)+,0x2(A0)                        | write register value
    BRA.B	SCC_INIT_LOOP                         | next register pair
SCC_INIT_FLUSH:
    BSET	#0x11,D7                               | set bit 17: SCC initialized
    LEA.L	(SCCRd_Base).L,A0                     | A0 = SCC read base
    MOVE.B	0x6(A0),D0                           | flush Rx buffer (read RR8)
    LEA.L	(VIA_Base).L,A1                       | A1 = VIA base address
    MOVE.B	#0x9,0x600(A1)                       | VIA PCR: CB2 output mode (sound)
    MOVE.B	0x1E00(A1),D0                        | D0 = VIA port B (vBufB)
    BSET	#0x3,D0                                | set bit 3: enable sound output
    MOVE.B	D0,0x1E00(A1)                        | write back to vBufB
    JMP	(A6)                                    | tail-call return from SCC_INIT_FLUSH via A6
| SCC_INIT_REGS - SCC channel B init register table
| Format: pairs of (register_number, value), terminated by 0xFF.
| Configures 9600 baud, 8N1 for manufacturing test serial link.
SCC_INIT_REGS:
    .short	0x09C0                               | WR9=0xC0: hardware reset
    .long	0x0F00044C                            | WR15=0x00, WR4=0x4C: x16 clock, 2 stop, no parity
    .long	0x0B500E00                            | WR11=0x50: Rx/Tx clock = BRG, WR14=0x00
    .long	0x0C0A0D00                            | WR12=0x0A, WR13=0x00: BRG divisor = 10 (9600 baud)
    .long	0x0E010A00                            | WR14=0x01: BRG enable, WR10=0x00
    .long	0x03C105EA                            | WR3=0xC1: Rx 8 bits enable, WR5=0xEA: Tx 8 bits enable
    .long	0x0100FFFF                            | WR1=0x00: no interrupts, 0xFF: end sentinel
| VIA_T1_INIT_BEEP - init VIA Timer 1 for periodic beep
|
| Configures Timer 1 in free-run mode with maximum interval (0xFFFF).
| The timer generates periodic interrupts used for boot beep timing.
VIA_T1_INIT_BEEP:
    LEA.L	(VIA_Base).L,A2                       | A2 = VIA base address
    CLR.B	0x1600(A2)                            | vT1CH = 0: clear timer 1 high latch
    MOVE.B	#0x20,0x1C00(A2)                     | vACR: Timer 1 free-run mode
    MOVE.B	#0xFF,0x1000(A2)                     | vT1CL = 0xFF: timer 1 counter low
    MOVE.B	#0xFF,0x1200(A2)                     | vT1CH = 0xFF: timer 1 counter high
    JMP	(A6)                                    | tail-call return from VIA_T1_INIT_BEEP via A6
| VIA_T1_CHECK_RELOAD - check/reload VIA Timer 1 for beep countdown
|
| Checks if Timer 1 has expired (IFR bit 5). If expired, reloads
| timer and decrements the beep countdown in D4 high word.
| Entry: D0 = reload count (used when countdown reaches 0)
| Exit: D0 bit 15 set if countdown expired
VIA_T1_CHECK_RELOAD:
    BCLR	#0xF,D0                                | clear expired flag
    LEA.L	(VIA_Base).L,A2                       | A2 = VIA base address
    BTST	#0x5,0x1A00(A2)                        | vIFR bit 5: Timer 1 fired?
    BEQ.B	VIA_T1_RETURN                         | no: return (not expired)
    MOVE.B	#0x20,0x1C00(A2)                     | vACR: Timer 1 free-run mode (reload)
    MOVE.B	#0xFF,0x1000(A2)                     | vT1CL = 0xFF: reload low
    MOVE.B	#0xFF,0x1200(A2)                     | vT1CH = 0xFF: reload high, clear IFR
    SWAP.W	D4                                   | access beep countdown (D4 high)
    SUBQ.W	#0x1,D4                              | decrement countdown
    BPL.B	VIA_T1_RESTORE_D4                     | still counting: return
    MOVE.W	D0,D4                                | reload countdown from D0
    BSET	#0xF,D0                                | set expired flag (countdown reached 0)
VIA_T1_RESTORE_D4:
    SWAP.W	D4                                   | restore D4 layout
VIA_T1_RETURN:
    JMP	(A6)                                    | tail-call return from VIA_T1_RETURN via A6
| DFAC_BEEP_TONE - beep tone generation via DFAC (Apple Sound Chip)
|
| Generates a multi-tone beep by programming the DFAC sound
| attenuator through the VIA shift register. Encodes D7 (4 bytes),
| D6 (4 bytes), and a "DH" prefix + checksum (4 bytes) as 12
| individual DFAC channel/volume commands.
DFAC_BEEP_TONE:
    MOVEA.L	A6,A4                               | A4 = save return address
    LEA.L	DFAC_TONE_INIT(PC),A6                 | set return address
    JMP	DFAC_INIT(PC)                           | init DFAC via VIA shift register
DFAC_TONE_INIT:
    MOVEQ.L	#0x0,D4                             | D4 = 0 (checksum accumulator)
    MOVEQ.L	#0x0,D3                             | D3 = 0 (byte counter)
| Encode D7 flags as 4 DFAC commands (bytes 0-3)
DFAC_ENCODE_D7:
    ROL.L	#0x8,D7                               | rotate next byte to low position
    MOVE.B	D7,D2                                | D2 = byte value
    MOVE.B	D3,D1                                | D1 = channel number
    LEA.L	DFAC_D7_NEXT(PC),A6                   | set return address
    JMP	DFAC_SEND_CMD(PC)                       | send DFAC command
DFAC_D7_NEXT:
    ADDQ.W	#0x1,D3                              | advance channel counter
    CMPI.W	#0x4,D3                              | all 4 D7 bytes sent?
    BLT.B	DFAC_ENCODE_D7                        | no: send next byte
| Encode D6 error code as 4 DFAC commands (bytes 4-7)
DFAC_ENCODE_D6:
    ROL.L	#0x8,D6                               | rotate next byte to low position
    MOVE.B	D6,D2                                | D2 = byte value
    MOVE.B	D3,D1                                | D1 = channel number
    LEA.L	DFAC_D6_NEXT(PC),A6                   | set return address
    JMP	DFAC_SEND_CMD(PC)                       | send DFAC command
DFAC_D6_NEXT:
    ADDQ.W	#0x1,D3                              | advance channel counter
    CMPI.W	#0x8,D3                              | all 4 D6 bytes sent?
    BLT.B	DFAC_ENCODE_D6                        | no: send next byte
| Encode "DH" prefix + checksum as 4 DFAC commands (bytes 8-11)
    MOVE.L	#0x44480000,D5                       | D5 = 'D','H',0,0 (prefix)
    MOVE.W	D4,D5                                | D5 low = checksum
DFAC_ENCODE_DH:
    ROL.L	#0x8,D5                               | rotate next byte to low position
    MOVE.B	D5,D2                                | D2 = byte value
    MOVE.B	D3,D1                                | D1 = channel number
    LEA.L	DFAC_DH_NEXT(PC),A6                   | set return address
    JMP	DFAC_SEND_CMD(PC)                       | send DFAC command
DFAC_DH_NEXT:
    ADDQ.W	#0x1,D3                              | advance channel counter
    CMPI.W	#0xC,D3                              | all 12 bytes sent?
    BLT.B	DFAC_ENCODE_DH                        | no: send next byte
    JMP	(A4)                                    | all tones generated: return
| VIA_BITBANG_8BITS - shift 8 bits out via VIA port A bit-bang
|
| Sends D1 (8 bits) to the DFAC sound attenuator via VIA port A,
| bit-banging the serial data through the shift register protocol.
| Bit 1 of VIA port A is the clock, bit 0 is data.
| Called by: DFAC_SEND_CMD, DFAC_SEND_LOWBYTE, RTC_WRITE_CMD_SENT, DFAC_INIT, DFAC_INIT_BYTE2
VIA_BITBANG_8BITS:
    LEA.L	(VIA_Base).L,A0                       | A0 = VIA base (port A at offset 0)
    MOVEQ.L	#0x7,D0                             | D0 = 7 (8 bits to shift)
VIA_BITBANG_LOOP:
    SWAP.W	D0                                   | save bit counter in high word
    MOVE.B	(A0),D0                              | D0 = current VIA port A value
    ROR.B	#0x1,D0                               | rotate bit 0 to carry (prep for data)
    ROXL.B	#0x1,D1                              | shift next data bit from D1 into X
    ROXL.B	#0x1,D0                              | shift X bit into VIA data position
    BCLR	#0x1,D0                                | clock low (bit 1 = DFAC clock)
    MOVE.B	D0,(A0)                              | write data + clock low
    BSET	#0x1,D0                                | clock high (rising edge latches data)
    MOVE.B	D0,(A0)                              | write data + clock high
    SWAP.W	D0                                   | restore bit counter
    DBF.W	D0,VIA_BITBANG_LOOP                   | loop for 8 bits
    JMP	(A6)                                    | tail-call return from VIA_BITBANG_LOOP via A6
| DFAC_SEND_CMD - send one DFAC command (channel + data)
|
| Programs the DFAC sound attenuator with channel D1 and data D2.
| Builds a 3-byte command: channel address, channel address (repeated),
| then data byte. Accumulates checksum in D4.
| Entry: D1 = channel (0-15), D2 = data byte
DFAC_SEND_CMD:
    MOVEA.L	A6,A5                               | A5 = save return address
    LEA.L	(VIA_Base).L,A0                       | A0 = VIA base address
    BCLR	#0x2,(A0)                              | clear bit 2: DFAC chip select low
    ANDI.W	#0xFF,D2                             | mask data to 8 bits
    ADD.W	D2,D4                                 | accumulate data into checksum
    ANDI.W	#0xF,D1                              | mask channel to 4 bits
    LSL.B	#0x2,D1                               | shift channel left by 2
    ADDI.W	#0xBF40,D1                           | build DFAC address byte
    ROR.W	#0x8,D1                               | position high byte for shift out
    ANDI.W	#0xFF7F,D1                           | clear parity bit
    LEA.L	DFAC_SEND_LOWBYTE(PC),A6              | set return address
    JMP	VIA_BITBANG_8BITS(PC)                   | shift out address byte (high)
DFAC_SEND_LOWBYTE:
    ROR.W	#0x8,D1                               | position low byte for shift out
    ANDI.W	#0xFF7F,D1                           | clear parity bit
    LEA.L	RTC_WRITE_CMD_SENT(PC),A6             | set return address
    JMP	VIA_BITBANG_8BITS(PC)                   | shift out address byte (low)
RTC_WRITE_CMD_SENT:
    MOVE.W	D2,D1                                | D1 = data byte
    LEA.L	DFAC_SEND_DESELECT(PC),A6             | set return address
    JMP	VIA_BITBANG_8BITS(PC)                   | shift out data byte
DFAC_SEND_DESELECT:
    LEA.L	(VIA_Base).L,A0                       | A0 = VIA base address
    BSET	#0x2,(A0)                              | set bit 2: DFAC chip select high
    JMP	(A5)                                    | tail-call return from DFAC_SEND_DESELECT via A5
| DFAC_INIT - initialize DFAC sound attenuator
|
| Sends initial volume/mode bytes to DFAC via VIA shift register.
| Sets up DFAC for tone generation.
DFAC_INIT:
    MOVEA.L	A6,A5                               | A5 = save return address
    MOVEQ.L	#0x35,D1                            | D1 = 0x35 (DFAC init command 1)
    MOVEQ.L	#0x55,D2                            | D2 = 0x55 (DFAC init command 2)
    LEA.L	(VIA_Base).L,A0                       | A0 = VIA base address
    BCLR	#0x2,(A0)                              | DFAC chip select low
    LEA.L	DFAC_INIT_BYTE2(PC),A6                | set return address
    JMP	VIA_BITBANG_8BITS(PC)                   | shift out init byte 1
DFAC_INIT_BYTE2:
    MOVE.W	D2,D1                                | D1 = init byte 2
    LEA.L	DFAC_INIT_DESELECT(PC),A6             | set return address
    JMP	VIA_BITBANG_8BITS(PC)                   | shift out init byte 2
DFAC_INIT_DESELECT:
    LEA.L	(VIA_Base).L,A0                       | A0 = VIA base address
    BSET	#0x2,(A0)                              | DFAC chip select high (deselect)
    JMP	(A5)                                    | tail-call return from DFAC_INIT_DESELECT via A5
| P_FindMemorySize - detect installed RAM size
|
| Probes RAM at various sizes from the MEMSIZE_PROBE_TBL table. For each
| entry, writes a pattern at the probed address and checks if the
| reference address (from MEMSIZE_REF_TBL) mirrors. Uses rotating patterns
| to detect data bus faults and address aliasing.
| Exit: D6 = detected RAM top address (0 = probe failed)
P_FindMemorySize:
    LEA.L	MEMSIZE_PROBE_TBL(PC),A0              | A0 = RAM size probe table
    LEA.L	MEMSIZE_REF_TBL(PC),A3                | A3 = reference address table
MEMSIZE_PROBE_NEXT:
    MOVEQ.L	#0x0,D0                             | clear D0 high bytes
    MOVE.B	(A0)+,D0                             | D0 = probe size byte
    MOVEA.L	(A3)+,A4                            | A4 = reference address for this probe
    CMPI.B	#0xFF,(A0)                           | end-of-table sentinel?
    BNE.B	MEMSIZE_DO_PROBE                      | no: probe this size
    LSL.L	#0x8,D0                               | D0 = size << 16 (default RAM size)
    LSL.L	#0x8,D0                               | (two shifts = 16 bits)
    MOVE.L	D0,D6                                | D6 = default RAM size
    BRA.B	MEMSIZE_RETURN                        | return default
MEMSIZE_DO_PROBE:
    MOVEQ.L	#0x0,D6                             | D6 = 0 (assume probe will succeed)
    LEA.L	MEMSIZE_PROBE_RESULT(PC),A5           | set return address for probe
    JMP	MEMSIZE_PROBE_BUS(PC)                   | probe RAM at this size
MEMSIZE_PROBE_RESULT:
    TST.L	D6                                    | probe found RAM? (D6 != 0)
    BNE.B	MEMSIZE_PROBE_NEXT                    | no RAM at this size: try next entry
    MOVE.L	A1,D6                                | D6 = probed address (= RAM size)
MEMSIZE_RETURN:
    JMP	(A6)                                    | return with D6 = RAM top
| MEMSIZE_PROBE_BUS - RAM probe subroutine: write pattern, verify readback
|
| Writes rotating patterns at the probe address (D0 << 16) and checks
| all 4 byte lanes for data bus integrity. Address A4 is a reference
| location monitored for aliasing (mirror detection).
MEMSIZE_PROBE_BUS:
    MOVEQ.L	#-0x1,D3                            | D3 = 0xFFFFFFFF (bus flush pattern)
    MOVEQ.L	#0x0,D2                             | clear D2
    MOVE.B	D0,D2                                | D2 = probe byte (replicated to longword)
    LSL.L	#0x8,D2                               | shift up
    MOVE.B	D0,D2                                | fill byte 2
    LSL.L	#0x8,D2                               | shift up
    MOVE.B	D0,D2                                | fill byte 1
    LSL.L	#0x8,D2                               | shift up
    MOVE.B	D0,D2                                | fill byte 0 (D2 = BBBBBBBB pattern)
    LSL.L	#0x8,D0                               | D0 = probe address (byte << 16)
    LSL.L	#0x8,D0                               | (two shifts)
    MOVEA.L	D0,A1                               | A1 = probe address
    MOVEQ.L	#0x7,D0                             | D0 = 7 (8 pattern rotations)
    CLR.L	(A4)                                  | clear reference location
MEMSIZE_BUS_LOOP:
    MOVE.L	D2,(A1)                              | write pattern at probe address
    TST.L	(A4)                                  | reference aliased? (mirror detected)
    BNE.B	MEMSIZE_BUS_DONE                      | yes: RAM not present at this size
    MOVE.L	D3,(ResetVector).W                   | flush bus with garbage pattern
    MOVE.L	D3,(ResetVector).W                   | (double write for bus settling)
    MOVE.L	(A1),D1                              | D1 = readback from probe address
    CMP.B	D1,D2                                 | byte 0 matches?
    BEQ.B	MEMSIZE_BUS_OK                        | yes: this lane OK
    ROR.L	#0x8,D1                               | rotate to check byte 1
    ROR.L	#0x8,D2                               | rotate pattern too
    CMP.B	D1,D2                                 | byte 1 matches?
    BEQ.B	MEMSIZE_BUS_OK                        | yes: this lane OK
    ROR.L	#0x8,D1                               | rotate to check byte 2
    ROR.L	#0x8,D2                               | rotate pattern too
    CMP.B	D1,D2                                 | byte 2 matches?
    BEQ.B	MEMSIZE_BUS_OK                        | yes: this lane OK
    ROR.L	#0x8,D1                               | rotate to check byte 3
    ROR.L	#0x8,D2                               | rotate pattern too
    CMP.B	D1,D2                                 | byte 3 matches?
    BNE.B	MEMSIZE_BUS_DONE                      | no: all lanes failed, no RAM here
MEMSIZE_BUS_OK:
    ROL.L	#0x1,D2                               | rotate pattern for next iteration
    DBF.W	D0,MEMSIZE_BUS_LOOP                   | test 8 rotations
    MOVE.L	A1,D6                                | D6 = probe address (RAM found here)
MEMSIZE_BUS_DONE:
    JMP	(A5)                                    | return to P_FindMemorySize
| MEMSIZE_PROBE_TBL - RAM size probe table
| Each byte is a RAM size code (shifted left 16 to form address).
| Table: 0x08, 0x10, 0x20, 0x28, 0x40, terminated by 0xFF.
| Corresponds to sizes: 512K, 1M, 2M, 2.5M, 4M.
MEMSIZE_PROBE_TBL:
    .short	0x0810                               | 512K, 1M probes
    .long	0x202840FF                            | 2M, 2.5M, 4M probes + terminator
| MEMSIZE_REF_TBL - reference addresses for mirror detection
| Each longword is the RAM address to monitor for aliasing.
MEMSIZE_REF_TBL:
    .long	0x00000000                            | probe 0: reference at 0
    .long	0x00000000                            | probe 1: reference at 0
    .long	0x00000000                            | probe 2: reference at 0
    .long	0x00200000                            | probe 3: reference at 2M
    .long	0x00000000                            | probe 4: reference at 0
| P_CheckRamFirst8 - data bus walking-ones test on first 8 bytes
|
| Writes rotating 1/0 patterns to addresses 0-7, then verifies
| readback matches. Tests all 32 data bus lines with 256 rotations.
| Entry: D6 = running error accumulator
| Exit: D6 = updated error bits (0 = all lanes OK)
P_CheckRamFirst8:
    MOVEQ.L	#0x1,D0                             | D0 = 0x00000001 (single-bit pattern)
    MOVE.L	D0,D1                                | D1 = complement start
    NEG.L	D1                                    | D1 = 0xFFFFFFFF
    SUBQ.L	#0x1,D1                              | D1 = 0xFFFFFFFE (inverted pattern)
    SUBA.L	A0,A0                                | A0 = 0 (RAM address 0)
    MOVE.W	#0xFF,D2                             | D2 = 255 (256 pattern rotations)
P_CheckRamFirst8_Loop:
    MOVEM.L	D0-D1,(A0)                          | write D0 at +0, D1 at +4
    EOR.L	D0,(A0)                               | XOR D0 with readback at +0 (expect 0)
    OR.L	(A0),D6                                | accumulate any mismatched bits
    EOR.L	D1,0x4(A0)                            | XOR D1 with readback at +4 (expect 0)
    OR.L	0x4(A0),D6                             | accumulate mismatched bits
    ROL.L	#0x1,D0                               | rotate pattern left (walk the 1)
    ROL.L	#0x1,D1                               | rotate complement left (walk the 0)
    DBF.W	D2,P_CheckRamFirst8_Loop              | loop 256 rotations
    MOVE.L	D6,D0                                | D0 = error bits
    SWAP.W	D0                                   | D0 = high word of errors
    OR.W	D0,D6                                  | fold high into low (16-bit result)
    ANDI.L	#0xFFFF,D6                           | mask to 16 bits
    JMP	(A6)                                    | tail-call return from P_CheckRamFirst8_Loop via A6
| P_ChecksumRom - verify 256 KB ROM checksum
|
| Sums all 16-bit words from ROM offset 4 through 0x3FFFF.
| XORs result with stored checksum at offset 0. D6 = 0 if match.
P_ChecksumRom:
    MOVEQ.L	#0x0,D0                             | D0 = 0 (word accumulator)
    MOVEQ.L	#0x0,D1                             | D1 = 0 (running 32-bit checksum)
    LEA.L	(0x400000).L,A0                       | A0 = ROM base (0x400000)
    MOVE.L	(A0)+,D4                             | D4 = stored checksum (ROM offset 0)
    MOVE.L	#0x1FFFE,D3                          | D3 = 0x1FFFE (128K words - 1 for header)
CKSUM_LOOP:
    MOVE.W	(A0)+,D0                             | D0 = next 16-bit ROM word
    ADD.L	D0,D1                                 | accumulate into 32-bit sum
    SUBQ.L	#0x1,D3                              | decrement word counter
    BNE.B	CKSUM_LOOP                            | loop over all ROM words
    NOP                                         | pipeline flush
    NOP                                         | pipeline flush
    EOR.L	D4,D1                                 | XOR sum with stored checksum
    BEQ.B	ROM_CKSUM_OK                          | zero = match: checksum OK
    MOVE.W	#0xFFFF,D6                           | non-zero: D6 = error flag
ROM_CKSUM_OK:
    JMP	(A6)                                    | return (D6 = 0 if OK)
| P_TestMemory0 - forward-direction memory test (pattern fill + XOR verify)
|
| Fills RAM range (A0..A1) with 12-byte repeating pattern from PAT_6DB6,
| then verifies using cascading XOR propagation. Any mismatched bits
| accumulate into D6.
| Entry: A0 = start, A1 = end
| Exit: D6 = error bits (0 = pass)
P_TestMemory0:
    MOVEA.L	A0,A2                               | A2 = fill pointer (starts at base)
    MOVE.L	A1,D3                                | D3 = end address
    SUB.L	A0,D3                                 | D3 = range size in bytes
| Calculate iteration counts for 12-byte MOVEM fill (64K outer x inner)
    MOVE.W	D3,D5                                | D5 = low word of size
    CLR.W	D3                                    | clear low word
    SWAP.W	D3                                   | D3 = high word of size
    DIVU.W	#0xC,D3                              | D3 = high / 12 (rem in high)
    SWAP.W	D3                                   | D3 = remainder
    SWAP.W	D5                                   | position for combined count
    MOVE.W	D3,D5                                | merge remainder into D5
    SWAP.W	D5                                   | restore D5
    SWAP.W	D3                                   | D3 = quotient (outer loops)
    DIVU.W	#0xC,D5                              | D5 = combined / 12 (inner loops)
    BNE.B	MEMTEST0_FILL_INIT                    | non-zero remainder: no adjust
    SUBQ.W	#0x1,D3                              | zero remainder: adjust outer count
MEMTEST0_FILL_INIT:
    SUBQ.W	#0x1,D5                              | adjust inner count for DBF
    MOVEQ.L	#0xC,D4                             | D4 = 12 (bytes per MOVEM iteration)
    MOVEM.L	PAT_6DB6,D0-D2                      | load 12-byte test pattern into D0-D2
| Fill loop: write 12 bytes at a time using MOVEM
MEMTEST0_FILL_LOOP:
    MOVEM.L	D0-D2,(A2)                          | write 12 pattern bytes
    ADDA.L	D4,A2                                | advance write pointer by 12
    DBF.W	D5,MEMTEST0_FILL_LOOP                 | inner loop
    DBF.W	D3,MEMTEST0_FILL_LOOP                 | outer loop (for >64K ranges)
| Handle tail bytes (range not multiple of 12): write remaining 4 or 8
    MOVEQ.L	#0x4,D4                             | D4 = 4 (tail offset for verify)
    CMPA.L	A2,A1                                | fill complete?
    BEQ.B	MEMTEST0_VERIFY_PASS1                 | yes: skip tail
    MOVE.L	D0,(A2)+                             | write 4 tail bytes
    MOVEQ.L	#0x8,D4                             | D4 = 8 (offset for 8-byte tail)
    CMPA.L	A2,A1                                | fill complete?
    BEQ.B	MEMTEST0_VERIFY_PASS1                 | yes: skip second tail word
    MOVE.L	D1,(A2)+                             | write 4 more tail bytes
    MOVEQ.L	#0x0,D4                             | D4 = 0 (all 12 bytes written)
| Verify phase: cascading XOR propagation (forward pass 1)
MEMTEST0_VERIFY_PASS1:
    MOVEA.L	A0,A2                               | A2 = verify pointer (start of range)
    MOVE.L	A1,D3                                | D3 = end address
    SUB.L	A0,D3                                 | D3 = range size
    SUBQ.L	#0x4,D3                              | adjust for longword count
    LSR.L	#0x2,D3                               | D3 = longword count
    MOVE.L	D3,D5                                | D5 = save count for pass 2
    EOR.L	D1,(A2)                               | seed first word with pattern XOR
    ADDI.L	#0xFFFFFFFF,D2                       | D2 = -1 (propagation seed)
MEMTEST0_VERIFY_LOOP_F1:
    MOVE.L	(A2)+,D2                             | D2 = current longword
    EOR.L	D2,(A2)                               | XOR into next longword (cascade)
    SUBQ.L	#0x1,D3                              | decrement counter
    BNE.B	MEMTEST0_VERIFY_LOOP_F1               | loop forward through range
| Verify phase: cascading XOR propagation (forward pass 2)
    MOVEA.L	A0,A2                               | A2 = back to start
    EOR.L	D0,(A2)                               | seed with second pattern
    ADDI.L	#0xFFFFFFFF,D2                       | D2 = -1 (propagation seed)
MEMTEST0_VERIFY_LOOP_F2:
    MOVE.L	(A2)+,D2                             | D2 = current longword
    EOR.L	D2,(A2)                               | XOR into next (cascade)
    SUBQ.L	#0x1,D5                              | decrement counter
    BNE.B	MEMTEST0_VERIFY_LOOP_F2               | loop forward through range
| Compare final 12 bytes against expected pattern (verify complete)
    MOVEM.L	-0xC(A1),D0-D2                      | D0-D2 = last 12 bytes of range
    LEA.L	PAT_6DB6(PC),A4                       | A4 = expected pattern base
    MOVEM.L	0x0(A4,D4.W),D3-D5                  | D3-D5 = expected (offset by tail)
    EOR.L	D3,D0                                 | XOR with expected (zero if match)
    EOR.L	D4,D1                                 | XOR word 2
    EOR.L	D5,D2                                 | XOR word 3
    OR.L	D2,D0                                  | combine mismatches
    OR.L	D1,D0                                  | combine all mismatches
    OR.L	D0,D6                                  | accumulate into error register
    SWAP.W	D0                                   | fold high word
    OR.W	D0,D6                                  | fold into 16-bit result
    ANDI.L	#0xFFFF,D6                           | mask to 16 bits
    JMP	(A6)                                    | return (D6 = 0 if pass)
| PAT_6DB6 - 12-byte test pattern for P_TestMemory0
| Repeating 3-bit sequence (110, 101, 011) exercises every data bit.
PAT_6DB6:
    .short	0x6DB6                               | pattern word 0
    .long	0xDB6DB6DB                            | pattern longword 1
    .long	0x6DB6DB6D                            | pattern longword 2
    .long	0xB6DB6DB6                            | pattern longword 3
    .long	0xDB6DB6DB                            | pattern longword 4
    .short	0x6DB6                               | pattern word 5 (tail)
| MEMTEST_REVERSE - reverse-direction memory test (pattern fill + XOR verify)
|
| Same algorithm as P_TestMemory0 but fills from end to start using
| MOVEM -(A3) and verifies backwards. Tests for direction-sensitive
| memory faults (e.g., refresh timing differences by address order).
| Entry: A0 = start, A1 = end
| Exit: D6 = error bits (0 = pass)
MEMTEST_REVERSE:
    MOVEA.L	A1,A3                               | A3 = fill pointer (starts at end)
    MOVE.L	A1,D3                                | D3 = end address
    SUB.L	A0,D3                                 | D3 = range size in bytes
| Calculate iteration counts (same as P_TestMemory0)
    MOVE.W	D3,D5                                | D5 = low word of size
    CLR.W	D3                                    | clear low word
    SWAP.W	D3                                   | D3 = high word of size
    DIVU.W	#0xC,D3                              | D3 = high / 12
    SWAP.W	D3                                   | D3 = remainder
    SWAP.W	D5                                   | position for combined count
    MOVE.W	D3,D5                                | merge remainder
    SWAP.W	D5                                   | restore D5
    SWAP.W	D3                                   | D3 = quotient (outer loops)
    DIVU.W	#0xC,D5                              | D5 = inner loop count
    BNE.B	MEMTEST_REV_FILL_INIT                 | non-zero remainder: no adjust
    SUBQ.W	#0x1,D3                              | adjust outer count
MEMTEST_REV_FILL_INIT:
    SUBQ.W	#0x1,D5                              | adjust for DBF
    MOVEQ.L	#0xC,D4                             | D4 = 12 bytes per iteration
    MOVEM.L	MEMTEST_REV_PATTERN,D0-D2           | load reverse-test pattern
| Reverse fill: write 12 bytes at a time descending from end
MEMTEST_REV_FILL_LOOP:
    MOVEM.L	D0-D2,-(A3)                         | write 12 bytes descending
    DBF.W	D5,MEMTEST_REV_FILL_LOOP              | inner loop
    DBF.W	D3,MEMTEST_REV_FILL_LOOP              | outer loop
| Handle head tail bytes (if range not multiple of 12)
    MOVEQ.L	#0x8,D4                             | D4 = 8 (tail offset)
    CMPA.L	A3,A0                                | fill reached start?
    BEQ.B	MEMTEST_REV_VERIFY_INIT               | yes: skip tail
    MOVE.L	D2,-(A3)                             | write 4 tail bytes
    MOVEQ.L	#0x4,D4                             | D4 = 4
    CMPA.L	A3,A0                                | fill complete?
    BEQ.B	MEMTEST_REV_VERIFY_INIT               | yes: skip
    MOVE.L	D1,-(A3)                             | write 4 more tail bytes
    MOVEQ.L	#0x0,D4                             | D4 = 0 (all 12 written)
| Reverse verify: cascading XOR propagation (backward pass 1)
MEMTEST_REV_VERIFY_INIT:
    MOVEA.L	A1,A3                               | A3 = end - 4 (verify start)
    SUBQ.L	#0x4,A3                              | point to last longword
    MOVE.L	A3,D3                                | D3 = address
    SUB.L	A0,D3                                 | D3 = range size - 4
    LSR.L	#0x2,D3                               | D3 = longword count
    MOVE.L	D3,D5                                | D5 = save count for pass 2
    EOR.L	D1,(A3)                               | seed last word with pattern XOR
    ADDI.L	#0xFFFFFFFF,D0                       | D0 = -1 (propagation seed)
MEMTEST_REV_VERIFY_LOOP_B1:
    MOVE.L	(A3),D0                              | D0 = current longword
    EOR.L	D0,-(A3)                              | XOR backward into previous
    SUBQ.L	#0x1,D3                              | decrement counter
    BNE.B	MEMTEST_REV_VERIFY_LOOP_B1            | loop backward
| Reverse verify: cascading XOR propagation (backward pass 2)
    MOVEA.L	A1,A3                               | A3 = end - 4
    SUBQ.L	#0x4,A3                              | point to last longword
    EOR.L	D2,(A3)                               | seed with second pattern
    ADDI.L	#0xFFFFFFFF,D0                       | D0 = -1 (propagation seed)
MEMTEST_REV_VERIFY_LOOP_B2:
    MOVE.L	(A3),D0                              | D0 = current longword
    EOR.L	D0,-(A3)                              | XOR backward
    SUBQ.L	#0x1,D5                              | decrement counter
    BNE.B	MEMTEST_REV_VERIFY_LOOP_B2            | loop backward
| Compare first 12 bytes against expected pattern
    MOVEM.L	(A0),D0-D2                          | D0-D2 = first 12 bytes
    LEA.L	MEMTEST_REV_PATTERN(PC),A4            | A4 = expected pattern base
    MOVEM.L	0x0(A4,D4.W),D3-D5                  | D3-D5 = expected (offset by tail)
    EOR.L	D3,D0                                 | XOR with expected
    EOR.L	D4,D1                                 | XOR word 2
    EOR.L	D5,D2                                 | XOR word 3
    OR.L	D2,D0                                  | combine mismatches
    OR.L	D1,D0                                  | combine all
    OR.L	D0,D6                                  | accumulate into error register
    SWAP.W	D0                                   | fold high word
    OR.W	D0,D6                                  | fold into 16-bit result
    ANDI.L	#0xFFFF,D6                           | mask to 16 bits
    JMP	(A6)                                    | return (D6 = 0 if pass)
| MEMTEST_REV_PATTERN - 12-byte test pattern for MEMTEST_REVERSE (reverse test)
MEMTEST_REV_PATTERN:
    .short	0x6DB6                               | pattern word 0
    .long	0xDB6DB6DB                            | pattern longword 1
    .long	0x6DB6DB6D                            | pattern longword 2
    .long	0xB6DB6DB6                            | pattern longword 3
    .long	0xDB6DB6DB                            | pattern longword 4
    .short	0x6DB6                               | pattern word 5 (tail)
| ROM_CKSUM_PER_BYTE - per-byte ROM checksum verification
|
| Computes separate even-byte and odd-byte sums over the 256 KB ROM,
| then compares each against expected values stored at ROM offset 0x30.
| Sets D6 bits 0-3 for each checksum that fails.
ROM_CKSUM_PER_BYTE:
    LEA.L	(0x400030).L,A1                       | A1 = ROM offset 0x30 (first section end)
    LEA.L	(0x400000).L,A0                       | A0 = ROM base
    MOVE.L	(A0)+,D0                             | skip stored checksum at offset 0
    MOVEA.L	A1,A2                               | A2 = expected checksums at offset 0x30
    MOVEQ.L	#0x0,D0                             | D0 = 0 (even-byte sum accumulator)
    MOVEQ.L	#0x0,D1                             | D1 = 0 (odd-byte sum accumulator)
    MOVEQ.L	#0x0,D2                             | clear D2 (reserved)
    MOVEQ.L	#0x0,D3                             | clear D3 (reserved)
    MOVEQ.L	#0x0,D4                             | clear D4 (byte extract temp)
    MOVEQ.L	#0x0,D5                             | clear D5 (word read temp)
| Sum first section: ROM offset 4 through 0x30
ROM_CKSUM_SEC1_LOOP:
    MOVE.W	(A0)+,D5                             | D5 = next ROM word
    MOVE.B	D5,D4                                | D4 = low byte (odd address)
    ADD.L	D4,D1                                 | accumulate odd-byte sum
    LSR.L	#0x8,D5                               | D5 = high byte (even address)
    MOVE.B	D5,D4                                | D4 = even byte
    ADD.L	D4,D0                                 | accumulate even-byte sum
    CMPA.L	A0,A1                                | reached offset 0x30?
    BGT.B	ROM_CKSUM_SEC1_LOOP                   | no: continue summing
    ADDA.W	#0x10,A0                             | skip 16 bytes (checksum storage area)
    LEA.L	(0x440000).L,A1                       | A1 = ROM end (0x440000)
| Sum second section: ROM offset 0x40 through end
ROM_CKSUM_SEC2_LOOP:
    MOVE.W	(A0)+,D5                             | D5 = next ROM word
    MOVE.B	D5,D4                                | D4 = low byte (odd)
    ADD.L	D4,D1                                 | accumulate odd-byte sum
    LSR.L	#0x8,D5                               | D5 = high byte (even)
    MOVE.B	D5,D4                                | D4 = even byte
    ADD.L	D4,D0                                 | accumulate even-byte sum
    CMPA.L	A0,A1                                | reached ROM end?
    BGT.B	ROM_CKSUM_SEC2_LOOP                   | no: continue
| Verify: compare computed sums against expected (4 longwords at 0x30)
    MOVE.L	(A2)+,D4                             | D4 = expected even-byte sum
    EOR.L	D4,D0                                 | XOR with computed (0 = match)
    BEQ.B	ROM_CKSUM_CHK_ODD                     | match: skip error
    BSET	#0x0,D6                                | set error bit 0: even sum mismatch
ROM_CKSUM_CHK_ODD:
    MOVE.L	(A2)+,D4                             | D4 = expected odd-byte sum
    EOR.L	D4,D1                                 | XOR with computed
    BEQ.B	ROM_CKSUM_CHK_3                       | match: skip error
    BSET	#0x1,D6                                | set error bit 1: odd sum mismatch
ROM_CKSUM_CHK_3:
    MOVE.L	(A2)+,D4                             | D4 = expected checksum 3
    EOR.L	D4,D2                                 | XOR with computed
    BEQ.B	ROM_CKSUM_CHK_4                       | match: skip error
    BSET	#0x2,D6                                | set error bit 2
ROM_CKSUM_CHK_4:
    MOVE.L	(A2)+,D4                             | D4 = expected checksum 4
    EOR.L	D4,D3                                 | XOR with computed
    BEQ.B	ROM_CKSUM_DONE                        | match: skip error
    BSET	#0x3,D6                                | set error bit 3
ROM_CKSUM_DONE:
    JMP	(A6)                                    | return (D6 bits 0-3 = results)
| MEMTEST_ZEROONES - multi-pass zero/ones RAM test
|
| Five-pass test: fill with 0, verify 0, XOR to all-1s, verify all-1s
| (forward+backward), then verify zeros again. Tests for stuck bits,
| coupling faults, and address-decoder errors.
| Entry: A0 = start, A1 = end
| Exit: D6 = error bits (0 = pass)
MEMTEST_ZEROONES:
    MOVEQ.L	#0x0,D0                             | D0 = 0 (zero fill pattern)
    MOVEQ.L	#-0x1,D1                            | D1 = 0xFFFFFFFF (ones pattern)
    MOVEA.L	A0,A2                               | A2 = write pointer
    MOVE.L	A1,D2                                | D2 = end address
    SUB.L	A0,D2                                 | D2 = range size in bytes
    LSR.L	#0x2,D2                               | D2 = longword count
    MOVE.L	D2,D3                                | D3 = save count for reuse
| Pass 1: fill entire range with zeros (forward)
MEMTEST_ZO_FILL_LOOP:
    MOVE.L	D0,(A2)+                             | write zero longword
    SUBQ.L	#0x1,D2                              | decrement counter
    BNE.B	MEMTEST_ZO_FILL_LOOP                  | loop through range
| Pass 2: verify zeros, then XOR to all-1s (forward)
    MOVE.L	D3,D2                                | reload count
    MOVEA.L	A0,A2                               | reset pointer to start
MEMTEST_ZO_PASS2:
    TST.L	(A2)                                  | read: should be zero
    BNE.B	MEMTEST_ZO_FAULT                      | non-zero: stuck-at-1 fault
    EOR.L	D1,(A2)+                              | XOR with 0xFFFF: set to all-1s
    SUBQ.L	#0x1,D2                              | decrement counter
    BNE.B	MEMTEST_ZO_PASS2                      | loop forward
| Pass 3: verify all-1s, XOR back to zeros (backward)
    MOVE.L	D3,D2                                | reload count
MEMTEST_ZO_REVERIFY_BACK:
    EOR.L	D1,-(A2)                              | XOR with 0xFFFF: should yield 0
    BNE.B	MEMTEST_ZO_FAULT                      | non-zero: data retention fault
    SUBQ.L	#0x1,D2                              | decrement counter
    BNE.B	MEMTEST_ZO_REVERIFY_BACK              | loop backward
| Pass 4: verify zeros, XOR to all-1s again (forward)
    MOVE.L	D3,D2                                | reload count
MEMTEST_ZO_PASS4:
    TST.L	(A2)                                  | read: should be zero
    BNE.B	MEMTEST_ZO_FAULT                      | non-zero: fault
    EOR.L	D1,(A2)+                              | set to all-1s again
    SUBQ.L	#0x1,D2                              | decrement counter
    BNE.B	MEMTEST_ZO_PASS4                      | loop forward
| Pass 5: verify all-1s, XOR back to zeros (backward)
    MOVE.L	D3,D2                                | reload count
MEMTEST_ZO_PASS5:
    EOR.L	D1,-(A2)                              | XOR: should yield 0
    BNE.B	MEMTEST_ZO_FAULT                      | non-zero: fault
    SUBQ.L	#0x1,D2                              | decrement counter
    BNE.B	MEMTEST_ZO_PASS5                      | loop backward
| Pass 6: final verify zeros (forward)
    MOVE.L	D3,D2                                | reload count
MEMTEST_ZO_FINAL_VERIFY:
    TST.L	(A2)+                                 | read: should be zero
    BNE.B	MEMTEST_ZO_FAULT                      | non-zero: fault
    SUBQ.L	#0x1,D2                              | decrement counter
    BNE.B	MEMTEST_ZO_FINAL_VERIFY               | loop forward
    JMP	(A6)                                    | all passes OK: return (D6 unchanged)
| MEMTEST_ZO_FAULT - test failure: accumulate error bits
| Called by: MEMTEST_ZO_PASS2, MEMTEST_ZO_REVERIFY_BACK, MEMTEST_ZO_PASS4, MEMTEST_ZO_PASS5, MEMTEST_ZO_FINAL_VERIFY
MEMTEST_ZO_FAULT:
    OR.L	(A2),D6                                | OR failing data into error register
    MOVE.L	D6,D0                                | D0 = error bits
    SWAP.W	D0                                   | fold high word
    OR.W	D0,D6                                  | fold into 16-bit result
    ANDI.L	#0xFFFF,D6                           | mask to 16 bits
    JMP	(A6)                                    | return (D6 = error bits)
| ADDRTEST_LINES - address line stuck-at test
|
| Writes unique values at power-of-2 addresses (4, 8, 16, ..., up
| to half of RAM) then reads back to verify no aliasing. Tests all
| address lines for stuck-at faults.
| Entry: SP = RAM top (from memory sizing)
| Exit: D6 = 0 if pass, non-zero if address line fault
ADDRTEST_LINES:
    MOVE.L	A7,D0                                | D0 = stack pointer (= RAM top)
    LEA.L	(0x80000).L,A2                        | A2 = 512K (default test limit)
    CMPI.L	#0x100000,D0                         | RAM > 1MB?
    BLE.B	ADDRTEST_CHK_STACK                    | no: use 512K limit
    LEA.L	(0x200000).L,A2                       | yes: use 2MB limit
ADDRTEST_CHK_STACK:
    CMPA.L	A2,A7                                | stack above test limit?
    BGT.B	ADDRTEST_PHASE1                       | yes: use full limit
    MOVE.L	A2,D0                                | D0 = test limit
    LSR.L	#0x1,D0                               | halve limit (stay below stack)
    MOVEA.L	D0,A2                               | A2 = reduced test limit
| Phase 1: write unique values at power-of-2 addresses (ascending)
ADDRTEST_PHASE1:
    CLR.L	(ResetStackPtr).W                     | clear address 0 (reference cell)
    MOVEQ.L	#0x4,D5                             | D5 = 4 (first power-of-2 address)
ADDRTEST_WRITE_LOOP:
    MOVEA.L	D5,A0                               | A0 = power-of-2 address
    MOVE.L	D5,(A0)                              | write address value as marker
    LSL.L	#0x1,D5                               | advance to next power of 2
    CMP.L	A2,D5                                 | past test limit?
    BLE.B	ADDRTEST_WRITE_LOOP                   | no: write next marker
| Phase 2: verify address 0 not corrupted (no stuck address lines)
    SUBA.L	A0,A0                                | A0 = 0
    MOVE.L	(A0),D0                              | D0 = value at address 0
    BNE.B	ADDRTEST_RETURN                       | non-zero: aliased, address fault
| Phase 3: verify each power-of-2 address still holds its marker
    MOVEQ.L	#0x4,D5                             | D5 = 4 (first address)
ADDRTEST_VERIFY_LOOP:
    MOVEA.L	D5,A0                               | A0 = power-of-2 address
    MOVE.L	(A0),D0                              | D0 = readback value
    EOR.L	D5,D0                                 | XOR with expected marker (0 = match)
    BNE.B	ADDRTEST_RETURN                       | mismatch: address line fault
    LSL.L	#0x1,D5                               | next power of 2
    CMP.L	A2,D5                                 | past test limit?
    BLE.B	ADDRTEST_VERIFY_LOOP                  | no: verify next
| Phase 4: reverse-write markers (descending power-of-2 addresses)
    MOVE.L	A2,D5                                | D5 = test limit
    LSL.L	#0x1,D5                               | start above limit
ADDRTEST_REVERSE_WRITE:
    LSR.L	#0x1,D5                               | descend to next power of 2
    CMPI.L	#0x4,D5                              | reached bottom (address 4)?
    BLT.B	ADDRTEST_VERIFY_REF                   | yes: done descending
    MOVEA.L	D5,A0                               | A0 = address
    MOVE.L	D5,(A0)                              | write marker (address value)
    BRA.B	ADDRTEST_REVERSE_WRITE                | continue descending
| Phase 5: verify address 0 not corrupted (reverse-order check)
ADDRTEST_VERIFY_REF:
    SUBA.L	A0,A0                                | A0 = 0
    MOVE.L	(A0),D0                              | D0 = value at address 0
    BNE.B	ADDRTEST_RETURN                       | non-zero: address fault
| Phase 6: verify markers after reverse write
    MOVEQ.L	#0x4,D5                             | D5 = 4
ADDRTEST_REVERSE_VERIFY:
    MOVEA.L	D5,A0                               | A0 = power-of-2 address
    MOVE.L	(A0),D0                              | D0 = readback
    EOR.L	D5,D0                                 | XOR with expected marker
    BNE.B	ADDRTEST_RETURN                       | mismatch: fault
    LSL.L	#0x1,D5                               | next power of 2
    CMP.L	A2,D5                                 | past limit?
    BLE.B	ADDRTEST_REVERSE_VERIFY               | no: verify next
    MOVEQ.L	#0x0,D0                             | all passed: D0 = 0 (no error)
ADDRTEST_RETURN:
    MOVE.L	D0,D6                                | D6 = error code (0 = pass)
    JMP	(A6)                                    | tail-call return from ADDRTEST_RETURN via A6
| TEST_ALWAYS_PASS - success return (unconditional pass)
TEST_ALWAYS_PASS:
    MOVEQ.L	#0x0,D6                             | D6 = 0 (pass)
    JMP	(A6)                                    | tail-call return from TEST_ALWAYS_PASS via A6
| TEST_TABLE_COUNT - test dispatch table entry count
TEST_TABLE_COUNT:
    .short	0x0008                               | 8 test entries in dispatch table
| TEST_DISPATCH_TBL - test dispatch table (8 PC-relative offsets)
| Each word is a signed offset from TEST_DISPATCH_TBL to a test routine.
TEST_DISPATCH_TBL:
    .long	0xFC56FCF0                            | tests 0-1: P_CheckRamFirst8, P_ChecksumRom
    .long	0xFD4CFF84                            | tests 2-3: P_TestMemory0, MEMTEST_REVERSE
    .long	0xFEB6FE02                            | tests 4-5: ROM_CKSUM_PER_BYTE, MEMTEST_ZEROONES
    .long	0xFF26FFFA                            | tests 6-7: ADDRTEST_LINES, TEST_ALWAYS_PASS
| SYSTEMBEEP - _SysBeep trap handler
|
| Called by the Toolbox _SysBeep trap. If sound is active, flashes
| the menu bar instead. Otherwise generates a square-wave beep tone
| via the VIA sound hardware using BOOTBEEP.
SYSTEMBEEP:
    MOVEM.L	D0-D7/A1-A6,-(A7)                   | save all registers (except A0)
    TST.B	(SoundActive).W                       | sound driver active?
    BNE.B	SYSBEEP_FLASH                         | yes: flash menu bar instead
    TST.B	(SdVolume).W                          | sound volume > 0?
    BNE.B	SYSBEEP_AUDIBLE                       | yes: generate audible beep
| No sound hardware available: flash menu bar as visual alert
SYSBEEP_FLASH:
    TST.B	(WWExist).W                           | write-anywhere memory installed?
    BNE.B	SYSBEEP_EPILOG                        | yes: skip (no menu bar to flash)
    CLR.L	-(A7)                                 | push 0 (invert menu bar)
    _FlashMenuBar                               | invert menu bar (visual alert)
    SUBA.L	A0,A0                                | A0 = 0
    ADDQ.W	#0x8,A0                              | A0 = 8 ticks delay
    _Delay                                      | wait ~8/60 second
    _FlashMenuBar                               | restore menu bar
    BRA.B	SYSBEEP_EPILOG                        | done
| Generate audible beep via BOOTBEEP
SYSBEEP_AUDIBLE:
    MOVE.W	0x3C(A7),D0                          | D0 = beep duration (from stack param)
    BSR.W	BOOTBEEP                              | generate boot-style beep tone
SYSBEEP_EPILOG:
    MOVEM.L	(A7)+,D0-D7/A1-A6                   | restore all registers
    MOVEA.L	(A7)+,A0                            | A0 = return address
    ADDQ.W	#0x2,A7                              | pop duration parameter (2 bytes)
    JMP	(A0)                                    | tail-call return from SYSBEEP_EPILOG via A0
| BOOTBEEP - generate square wave beep tone
|
| Fills the sound buffer with a ~3 kHz square wave pattern, then
| smooths it with a FIR filter. The tone plays through the PWM
| DAC for D3 ticks. Code continues into interrupts.s region.
| Entry: D0 = beep duration in ticks
BOOTBEEP:
    MOVE.W	D0,D3                                | D3 = beep duration (ticks)
    LEA.L	(VIA_Base).L,A5                       | A5 = VIA base address
    LEA.L	(0x3FFD00).L,A0                       | A0 = sound buffer base (screen - 768)
    MOVEA.L	A0,A4                               | A4 = save buffer base for smoothing
    MOVE.W	SR,D5                                | D5 = current status register
    ANDI.W	#0x700,D5                            | D5 = IPL mask (interrupt level)

| BOOTBEEP continuation (entry from memtest.s BOOTBEEP):
| D5 = IPL mask, D3 = beep duration, A5 = VIA base, A0/A4 = sound buffer
    BNE.B	BEEP_POLL_VIA                         | IPL != 0: interrupts masked, poll VIA
    MOVE.L	(Ticks).W,D0                         | D0 = current tick count (VBL-synced)
| BootBeep: wait for Ticks change
| BootBeep: wait for Ticks change (VBL-synced buffer fill timing)
BEEP_WAIT_TICK:
    CMP.L	(Ticks).W,D0                          | tick count changed?
    BEQ.B	BEEP_WAIT_TICK                        | no: keep waiting
    BRA.B	BEEP_FILL_BUFFER                      | tick changed: fill buffer
| BEEP_POLL_VIA - VBL polling path (interrupts disabled during boot)
| Poll VIA IFR bit 1 (Timer 1) directly since no VBL interrupt yet.
BEEP_POLL_VIA:
    MOVEQ.L	#-0x1,D0                            | D0 = 0xFFFF (max polling count)
BEEP_POLL_TIMER_LOOP:
    BTST	#0x1,0x1A00(A5)                        | VIA IFR bit 1: Timer 1 fired?
    DBNE.W	D0,BEEP_POLL_TIMER_LOOP              | poll until timer fires or timeout
    MOVE.B	#0x2,0x1A00(A5)                      | clear Timer 1 interrupt flag
| BEEP_FILL_BUFFER - fill sound buffer with square wave pattern
| Uses 4-byte pattern {0xC0, 0x06, 0xFA, 0x40} repeated 5 times,
| 20 samples per byte = 400 bytes total. Creates ~3 kHz square wave.
BEEP_FILL_BUFFER:
    MOVE.W	#0xD00,D0                            | D0 = 3328 (sound DMA settling delay)
BEEP_DMA_DELAY:
    DBF.W	D0,BEEP_DMA_DELAY                     | wait for sound DMA to settle
    MOVEQ.L	#0x4,D0                             | D0 = 4 (5 pattern repetitions)
BEEP_FILL_REPEAT:
    MOVE.L	#0xC006FA40,D1                       | D1 = 4-byte square wave pattern
BEEP_FILL_CYCLE:
    MOVEQ.L	#0x13,D2                            | D2 = 19 (20 samples per byte)
BEEP_WRITE_SAMPLE:
    MOVE.B	D1,(A0)                              | write sample byte to sound buffer
    ADDQ.W	#0x2,A0                              | advance by 2 (alternating bytes)
    SUBQ.W	#0x1,D2                              | decrement sample counter
    BNE.B	BEEP_WRITE_SAMPLE                     | loop 20 samples per byte
    LSR.L	#0x8,D1                               | shift to next pattern byte
    BNE.B	BEEP_FILL_CYCLE                       | more bytes: continue cycling
    DBF.W	D0,BEEP_FILL_REPEAT                   | loop 5 repetitions
    BCLR	#0x7,(A5)                              | clear VIA port A bit 7 (sound enable)
    ADDQ.W	#0x1,D3                              | increment beep duration counter
    BRA.B	BEEP_WAIT_VBL                         | proceed to VBL sync wait
| BEEP_SMOOTH_FILTER - smooth sound buffer with 1:2:1 FIR filter
|
| Reduces aliasing artifacts in the square wave by averaging each
| sample with its neighbors: out[n] = (in[n-1] + 2*in[n] + in[n+1]) / 4.
| Then extends the smoothed 74-sample kernel to fill the full 370-byte buffer.
BEEP_SMOOTH_FILTER:
    MOVEA.L	A4,A0                               | A0 = output pointer (buffer base)
    LEA.L	0x92(A0),A1                           | A1 = source pointer (offset 0x92)
    MOVEQ.L	#0x49,D0                            | D0 = 73 (74 samples to smooth)
BEEP_FIR_LOOP:
    MOVE.B	(A1),D2                              | D2 = sample[n-1]
    ADDQ.W	#0x4,A1                              | advance to sample[n+1]
    MOVE.B	(A1),D1                              | D1 = sample[n+1]
    ADD.W	D1,D2                                 | D2 = sample[n-1] + sample[n+1]
    SUBQ.W	#0x2,A1                              | back to sample[n]
    MOVE.B	(A1),D1                              | D1 = sample[n] (center)
    ADD.W	D1,D2                                 | D2 += sample[n]
    ADD.W	D1,D2                                 | D2 += sample[n] (weight 2)
    ADDQ.W	#0x3,D2                              | round up: add 3 before divide
    ASR.W	#0x2,D2                               | D2 /= 4 (1:2:1 weighted average)
    MOVE.B	D2,(A0)                              | store smoothed sample
    ADDQ.W	#0x2,A0                              | advance output (every other byte)
    DBF.W	D0,BEEP_FIR_LOOP                      | loop 74 samples
| Extend smoothed data: replicate 74-sample kernel to fill full buffer
    MOVE.W	#0x127,D0                            | D0 = 295 (296 samples to extend)
BEEP_EXTEND_LOOP:
    MOVE.B	-0x4A(A0),(A0)                       | copy from 74 samples back (cycle)
    ADDQ.W	#0x2,A0                              | advance output pointer
    DBF.W	D0,BEEP_EXTEND_LOOP                   | loop to fill buffer
| BEEP_WAIT_VBL - wait for one VBL tick, then loop to smooth+refill
BEEP_WAIT_VBL:
    MOVEQ.L	#-0x1,D0                            | D0 = 0xFFFF (poll timeout)
    TST.W	D5                                    | interrupts enabled? (D5 = IPL mask)
    BNE.B	BEEP_VIA_POLL_LOOP                    | no: poll VIA directly
    MOVE.L	(Ticks).W,D0                         | D0 = current tick count
BEEP_TICK_WAIT:
    CMP.L	(Ticks).W,D0                          | tick changed? (VBL occurred)
    BEQ.B	BEEP_TICK_WAIT                        | no: keep waiting
    BRA.B	BEEP_DURATION_CHECK                   | tick changed: check duration
| VIA polling path (interrupts disabled)
BEEP_VIA_POLL_LOOP:
    BTST	#0x1,0x1A00(A5)                        | VIA IFR bit 1: Timer 1 fired?
    DBNE.W	D0,BEEP_VIA_POLL_LOOP                | poll until timer fires
    MOVE.B	#0x2,0x1A00(A5)                      | clear Timer 1 interrupt flag
| BEEP_DURATION_CHECK - one VBL complete; loop or silence and return
BEEP_DURATION_CHECK:
    DBF.W	D3,BEEP_SMOOTH_FILTER                 | more ticks: smooth + refill buffer
| Duration expired: fill buffer with silence (0x80 = center/quiet)
    MOVEA.L	A4,A0                               | A0 = sound buffer base
    MOVEQ.L	#-0x80,D0                           | D0 = 0x80 (silence level, signed)
    MOVE.W	#0x171,D1                            | D1 = 369 (370 samples to clear)
BEEP_SILENCE_LOOP:
    MOVE.B	D0,(A0)                              | write silence byte
    ADDQ.W	#0x2,A0                              | advance (every other byte)
    DBF.W	D1,BEEP_SILENCE_LOOP                  | loop to fill buffer
    RTS                                         | return from BOOTBEEP
| ERRORBEEP3 - error beep return stub (used by boot error paths)
ERRORBEEP3:
    JMP	(A6)                                    | return via A6
