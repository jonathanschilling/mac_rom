| ROM Checksum Verification and Memory Test
|
| Runs once during boot from vectors.s, before any RAM is trusted.
| Classic 1984 version: only does the ROM checksum here and returns
| via JMP (A6); the subsequent memory-test phases are called from
| vectors.s:IWM_INIT_DONE separately. Plus folds all phases into one
| routine (see src/plus/boot/memtest.s).
|
| Phase 1 (this file, ChecksumRomAndTestMemory / CKSUM_LOOP):
| Sum every 16-bit word of ROM except the stored checksum (first
| long), XOR with stored value -- Z=1 in CCR if match.
|
| Phase 2 (later, via ADDRLINE_TEST):
| Address-line stuck-at test: walk a single rotating bit through
| the low 128 RAM addresses; fails fast if a data line is stuck.
|
| Phase 3: MOVEP.W 0x55AA sanity check -- 32-bit readback.
|
| Phase 4: Three full-RAM pattern fills (0xDB6D / 0x6DB6 / 0xB6DB)
| using PATTERN_FILL_VERIFY as the ascending-write / descending-write
| / XOR-readback primitive; patterns chosen to catch adjacent-cell
| interactions in DRAM. Pattern descriptor table at $0766.
|
| Entry: A6 = return addr (no stack available).
| Exit: D1 = accumulated mismatch bits; Z=1 iff all tests pass.
|
| References:
| Inside Macintosh Vol II, Ch 1: Memory Manager - Memory Organization (p 19)

| ----------------------------------------------------------
| ChecksumRomAndTestMemory entry point (1984 original).
| A6 = return address (no stack available yet).
| Phase 1: sum every 16-bit word of ROM except the stored checksum.
ChecksumRomAndTestMemory:
        MOVEQ.L #0x0,D0                         | D0 = running 32-bit checksum accumulator
        MOVEQ.L #0x0,D1                         | D1 = word-read scratch
        LEA     VECTORS_CONT(PC),A0             | A0 = ROM start (offset 0)
        MOVE.L  (A0)+,D3                        | D3 = stored checksum (first long of ROM)
        MOVE    #0x7FFD,D2                      | D2 = 32765 words remaining (64KB/2 - 3)
CKSUM_LOOP:
        MOVE    (A0)+,D1                        | read next 16-bit ROM word
        ADD.L   D1,D0                           | accumulate into 32-bit checksum
        DBRA    D2,CKSUM_LOOP                   | loop over all remaining ROM words
        EOR.L   D3,D0                           | XOR with stored value (zero if match)
        JMP     (A6)                            | return via A6 (CCR set from XOR)

| ----------------------------------------------------------
| Address-line stuck-at test -- phase 2 of the memory test.
| Walks power-of-2 RAM addresses, writes 0xFFFF, checks that the
| value doesn't alias back to RAM base (stuck address line).
ADDRLINE_TEST:
        MOVEQ.L #0x0,D1                         | D1 = 0 (reference value at RAM base)
        ADDQ.W  #0x1,A4                         | A4 = 2 (phase 2: address-line test)
        MOVE.L  A3,A0                           | A0 = RAM base pointer
        MOVEQ.L #0x1,D2                         | D2 = 1 (rotating bit pattern)
        MOVEQ.L #0x7F,D3                        | D3 = 127 (128 bit positions to test)
ADDRLINE_TEST_LOOP:
        MOVE    D2,(A0)                         | write rotating bit pattern to RAM base
        MOVE    (A0),D1                         | read back
        EOR     D2,D1                           | D1 = 0 if readback matches
        BNE.W   MEMTEST_RETURN                  | mismatch: jump to failure report
        ROL     #0x1,D2                         | rotate pattern: next single bit
        DBRA    D3,ADDRLINE_TEST_LOOP           | test all 128 bit positions
        ADDQ.W  #0x1,A4                         | A4 = 3 (phase 3: parity-test setup)
        MOVE    #0x55AA,D2                      | test pattern 0x55AA (10101010/10101010)
        MOVEP.W D2,0(A0)                        | write pattern to odd-offset bytes
        MOVEP.W D2,1(A0)                        | write pattern to even-offset bytes
        MOVE.L  (A0),D1                         | read back 32 bits
        EORI.L  #0x5555AAAA,D1                  | XOR with expected (MOVEP.W pair readback)
        BNE.W   MEMTEST_RETURN                  | readback differed: fail memtest
        ADDQ.W  #0x1,A4                         | A4 = 4 (phase 4: full RAM pattern test)
        MOVEQ.L #0x0,D0                         | D0 = running error accumulator
        LEA     PAT_DESCRIPTORS(PC),A2          | A2 = pattern descriptor table
        MOVEM.L (A2),D2-D6                      | load first 3-word pattern into D2-D6
        LEA     PATTERN_PASS_2(PC),A5           | return to next pattern phase after verify
        BRA.W   PATTERN_FILL_VERIFY             | run pattern fill/verify

| ----------------------------------------------------------
| PATTERN_PASS_2 -- second RAM pattern pass (complementary bits)
PATTERN_PASS_2:
        MOVEM.L 4(A2),D2-D6                     | load second pattern (offset +4)
        LEA     PATTERN_PASS_3(PC),A5           | return to third pass after verify
        BRA.W   PATTERN_FILL_VERIFY             | run pattern fill/verify
PATTERN_PASS_3:                                 | third RAM pattern pass
        MOVEM.L 8(A2),D2-D6                     | load third pattern (offset +8)
        LEA     PATTERN_TESTS_DONE(PC),A5       | return to MEMTEST result report
        BRA.W   PATTERN_FILL_VERIFY             | run final pattern fill/verify

| ----------------------------------------------------------
| MEMTEST_RETURN / PATTERN_TESTS_DONE -- final result assembly
| All three RAM pattern passes have run; D0 has accumulated any bits
| that differed during readback. Combine high + low words, set Z flag,
| and return via A6 to the boot code. Z=1 means RAM passed.
| Called during boot (28,780 times in 30s trace).
PATTERN_TESTS_DONE:
        MOVEQ.L #0x0,D1                         | clear D1 high
        MOVE    D0,D1                           | D1 low = accumulated error bits (low word)
        SWAP    D0                              | D0 = high word of error accumulator
        OR      D0,D1                           | D1 = combined error (zero if all passed)
        CMPI    #-0x1,D1                        | saturated? (-1 means all-bad, shortcut)
        BNE.B   MEMTEST_RETURN                  | no: skip extra-pass in-place verify
        ADDQ.W  #0x1,A4                         | bump test phase (shortcut-pass signal)
        MOVE.L  A3,A0                           | A0 = RAM base
        MOVE.L  A0,A1                           | A1 = RAM base (verify source pointer)
        MOVEQ.L #-0x1,D2                        | D2 = 0xFFFFFFFF fill pattern
PATTERN_TESTS_FILL:                             | fill RAM with 0xFFFF words
        MOVE    D2,(A0)+                        | write 0xFFFF to next word
        DBRA    D2,PATTERN_TESTS_FILL           | fill 65536 words (entire 64K)
PATTERN_TESTS_VERIFY:                           | read back + compare
        MOVE    (A1)+,D3                        | read next word
        EOR     D2,D3                           | D3 = 0 if readback matches 0xFFFF
        OR      D3,D1                           | accumulate any mismatched bits
        DBRA    D2,PATTERN_TESTS_VERIFY         | check 65536 words
        BNE.B   MEMTEST_RETURN                  | errors found: report
        OR      D0,D1                           | combine high+low error words
MEMTEST_RETURN:
        TST     D1                              | Z=1 if all memtests passed
        JMP     (A6)                            | return to boot code

| ----------------------------------------------------------
| PATTERN_FILL_VERIFY -- fill RAM with 12-byte pattern
| and verify by XOR-readback. Each pattern is loaded from A2 in a
| descriptor table at PAT_DESCRIPTORS below.
| Entry: A2 = pattern descriptor (contains D1 count + A0/A1 ptrs at +28),
| D2-D6 = pattern bytes. A5 = return address.
PATTERN_FILL_VERIFY:
        MOVEM.L 28(A2),D1/A0-A1                 | load iteration count + fill pointers
FILL_LOOP:                                      | descending fill loop
        MOVEM.L D2-D4,(A0)                      | write 12 pattern bytes ascending
        ADDA.W  #0xC,A0                         | advance ascending pointer by 12 bytes
FILL_LOOP_DESC:
        MOVEM.L D4-D6,-(A1)                     | write 12 pattern bytes descending
        DBRA    D1,FILL_LOOP                    | continue until halves meet in middle
        MOVEM.L 28(A2),D1/A0-A1                 | reload pointers for verify pass
        SWAP    D1                              | D1 = saved verify count
VERIFY_LOOP:                                    | verify loop (12 bytes at a time)
        MOVEM.L (A0)+,D5-D7                     | read 12 bytes of RAM into D5-D7
        EOR.L   D2,D5                           | XOR with expected word 1 (zero if match)
        EOR.L   D3,D6                           | XOR with expected word 2
        EOR.L   D4,D7                           | XOR with expected word 3
        OR.L    D5,D6                           | combine mismatches 1-2
        OR.L    D6,D7                           | combine all mismatched bits
        OR.L    D7,D0                           | accumulate into running error register
        DBRA    D1,VERIFY_LOOP                  | verify full RAM
        MOVEM.L (A0)+,D5-D6                     | read tail 8 bytes
        EOR.L   D2,D5                           | XOR with pattern word 1
        EOR.L   D3,D6                           | XOR with pattern word 2
        OR.L    D5,D6                           | merge tail mismatches
        OR.L    D6,D0                           | fold tail into running error
        JMP     (A5)                            | return to pattern dispatch
| ----------------------------------------------------------
| PAT_DESCRIPTORS -- RAM pattern descriptor table
| 36 bytes describing three DRAM test patterns (DB6D / 6DB6 / B6DB)
| plus iteration counts. Encoded as a mix of bytes and 16-bit shorts
| that FDisasm rendered as misclassified "ADD D5,-0x4925(A5)" etc.
PAT_DESCRIPTORS:                                | pattern descriptor + data
        ADD     D5,-0x4925(A5)                  | bytes 0x4925 etc. encode pattern entry 1
        BLT.B   MEMTEST_RETURN                  | (fake instruction across data words)
        ADD     D5,-0x4925(A5)                  | pattern entry 1 continued
        .short  0x6DB6                          | pattern word (DRAM bit pattern 0x6DB6)
        ADD     D5,-0x4925(A5)                  | (bytes straddle into next pseudo-instr)
        .short  0x6DB6                          | pattern word (second occurrence)
        ADD     D5,-0x4925(A5)                  | (pattern table continues)
        BLT.B   FILL_LOOP_DESC                  | (mis-disassembled pattern byte pair)
        ADD     D5,-0x4925(A5)                  | (trailing pattern byte)
        MOVE.L  0x1555(A1),(A5)                 | pattern entry tail: 0x5555 repeated
        ORI     #0x0,-(A0)                      | padding / alignment (0x0000 0x0000)
        ORI     #0x0,-(A2)                      | padding / alignment (0x0000 0x0000)
