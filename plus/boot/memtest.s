| ROM Checksum Verification and Memory Test
|
| Verifies the ROM checksum (sum of 16-bit words from offset 4),
| then tests RAM with multiple passes (bus test, address line test,
| byte-write test). Called during cold boot before any RAM is trusted.
|
| Register conventions throughout:
| A3 = RAM base address (0x000000 after overlay cleared, 0x600000 during overlay)
| A4 = test phase number (1=ROM checksum, 2=address line test, 3=pattern test)
| A6 = return address (no stack available yet)
| A2 = current RAM end / test pointer
| A5 = return address for pattern fill subroutine (PATTERN_FILL_VERIFY)
|
| References:
| Inside Macintosh Vol II, Ch 1: Memory Manager - Memory Organization (p 19)

| return address in A6
| Called during boot.
ChecksumRomAndTestMemory:
        MOVEQ.L #0x1,D0                         | set test selector to 1 (ROM checksum phase)
        MOVE.L  D0,A4                           | A4 holds test number, test 1 is ROM checksum
        MOVEQ.L #0x0,D0                         | D0 = accumulator for word reads
        MOVEQ.L #0x0,D1                         | D1 = running 32-bit checksum
        LEA.L   (0x400000).l,A0                 | A0 = ROM start (0x400000)
        MOVE.L  (A0)+,D3                        | D3 = expected checksum from ROM offset 0
        MOVE    #-0x3,D2                        | D2 = 0xFFFD = 65533 words remaining (128KB/2 - 1)
CKSUM_LOOP:
        MOVE    (A0)+,D0                        | read next 16-bit ROM word
        ADD.L   D0,D1                           | accumulate into 32-bit checksum
        DBF     D2,CKSUM_LOOP                   | loop over all ROM words after offset 4
        EOR.L   D3,D1                           | XOR sum with expected checksum (zero if match)
        MOVE    D1,D0                           | D0 = low word of result
        SWAP    D1                              | D1 = high word of result
        OR      D0,D1                           | combine both halves (zero only if both zero)
        BNE     MEMTEST_RETURN                  | checksum mismatch: fail with error code
        ADDQ.W  #0x1,A4                         | advance to test 2: address line stuck-at test
        CLR     (A3)                            | zero RAM base (reference cell for aliasing detection)
        MOVEQ.L #-0x1,D0                        | D0 = 0xFFFF test pattern (all bits set)
        MOVEQ.L #0x2,D1                         | D1 = 2: first address offset (A1, lowest address line)
        MOVEQ.L #0xF,D3                         | D3 = 15: test address lines A1 through A16
| Address line stuck-at-fault test: write 0xFFFF to each power-of-2 offset,
| check whether it bleeds through to address 0 (stuck address line = alias).
ADDRLINE_TEST:
        MOVE.L  A3,A2                           | A2 = RAM base
        ADDA.L  D1,A2                           | A2 = RAM base + 2^N (test address)
        ADD.L   D1,D1                           | advance to next power-of-2 offset
        MOVE    D0,(A2)                         | write 0xFFFF to power-of-2 address
        TST     (A3)                            | check if RAM base was corrupted (address alias)
        BNE.B   ADDRLINE_FAIL                   | non-zero at base: address line stuck, fail
        CLR     (A3)                            | re-clear base for next iteration
        EOR     D0,(A2)                         | toggle pattern at test address (expect zero)
        DBNE    D3,ADDRLINE_TEST                | loop unless data readback failed
        BEQ.B   RAM_SIZE_DETECT                 | all 16 address lines passed: continue to RAM sizing
ADDRLINE_FAIL:
        MOVE    (A3),D1                         | D1 = failing data (error code for diagnostic)
        BRA.B   MEMTEST_RETURN                  | report failure

| ----------------------------------------------------------
|
| RAM_SIZE_DETECT - RAM size detection via address mirror test
|
| Walks up in power-of-2 steps from the last address-line-test offset.
| When a write aliases back to address 0, that offset is the RAM size.
| Then verifies each RAM bank responds correctly to data pattern writes.
| Called during boot.
RAM_SIZE_DETECT:
        MOVE.L  A3,A2                           | A2 = RAM base
        ADDA.L  D1,A2                           | A2 = next power-of-2 boundary to probe
        CLR     (A3)                            | zero base cell for alias detection
        MOVE    D0,(A2)                         | write 0xFFFF at probe address
        TST     (A3)                            | did write alias back to address 0?
        BNE.B   RAM_SIZE_DONE                   | yes: probe wrapped around, A2 = total RAM size
        MOVE.L  A3,A2                           | A2 = RAM base (start of verified region)
        ASL.L   #0x2,D1                         | D1 = bank stride (4x probe offset, 256K per bank)
        MOVEQ.L #0x1,D2                         | D2 = bank number (starting at bank 1)
| Per-bank data pattern verification: write alternating patterns to each bank,
| then read back to confirm data bus integrity across all banks.
BANK_PATTERN_TEST:
        MOVEQ.L #0x5,D3                         | D3 = 5: six pattern iterations per bank
BANK_TOGGLE_LOOP:
        NOT     D2                              | toggle D2 between complementary bit patterns
        MOVE    D2,(A2)                         | write pattern to current bank's base
        CMP     (A2),D2                         | verify readback matches written pattern
        DBNE    D3,BANK_TOGGLE_LOOP             | retry with toggled pattern up to 6 times
        BNE.B   RAM_SIZE_DONE                   | readback mismatch: bank failed, stop sizing
        MOVE.L  A3,A1                           | A1 = RAM base (scan start)
        MOVEQ.L #0x0,D3                         | D3 = 0: expected sequence counter
| Verify no bank-to-bank address aliasing: each bank should hold its
| unique sequence number (D3) written during previous iterations.
BANK_ALIAS_CHECK:
        ADDQ.W  #0x1,D3                         | D3 = next expected bank sequence value
        CMP     (A1),D3                         | does this bank still hold its unique value?
        BNE.B   RAM_SIZE_DONE                   | mismatch: bank aliases with another, stop
        ADDA.L  D1,A1                           | advance A1 to next bank
        CMP     D3,D2                           | have we checked all banks found so far?
        BGT.B   BANK_ALIAS_CHECK                | more banks to verify: continue
        ADDA.L  D1,A2                           | A2 += bank stride (extend verified RAM region)
        ADDQ.W  #0x1,D2                         | D2 = next bank number to test
        CMPI    #0x8,D2                         | tested all 8 possible banks (8x256K = 2MB per row)?
        BLE.B   BANK_PATTERN_TEST               | more banks possible: test next one
| RAM_SIZE_DONE - RAM sizing complete, A2 = top of verified RAM
RAM_SIZE_DONE:
        ADDQ.W  #0x1,A4                         | advance to test 3: full RAM pattern fill/verify
        MOVEQ.L #0x0,D0                         | D0 = error accumulator (0 = no errors yet)
        CMPI.L  #0x400000,0x2AE(A3)             | check ROMBase: is ROM at standard 0x400000?

        BEQ.B   PATTERN_TESTS_DONE              | yes: skip pattern test (overlay still active)
        TST.B   D6                              | D6 bit 7: warm start flag from boot code
        BPL.B   PATTERN_TESTS_DONE              | warm start: skip destructive RAM pattern test
        LEA.L   PAT_DB6D(PC),A0                 | A0 = first pattern (0xDB6D = 1101_1011 0110_1101)
        LEA.L   PATTERN_PASS_2(PC),A5           | return to PATTERN_PASS_2 after first pattern pass
        BRA.B   PATTERN_FILL_VERIFY             | fill/verify RAM with pattern PAT_DB6D

| ----------------------------------------------------------
|
| PATTERN_PASS_2 - second pattern pass: uses PAT_6DB6 (0x6DB6DB... walking-ones)
|
| Called during boot.
PATTERN_PASS_2:
        LEA.L   PAT_6DB6(PC),A0                 | A0 = second pattern (6DB6DB = 0110_1101...)
        LEA.L   PATTERN_PASS_3(PC),A5           | return to PATTERN_PASS_3 after second pass
        BRA.B   PATTERN_FILL_VERIFY             | fill/verify RAM with pattern PAT_6DB6

| ----------------------------------------------------------
|
| PATTERN_PASS_3 - third pattern pass: uses PAT_B6DB (0xB6DB = 1011_0110...)
|
| The three patterns (DB6D, 6DB6, B6DB) together exercise every bit
| position as both 0 and 1, ensuring no stuck data bits in DRAM.
| Called during boot.
PATTERN_PASS_3:
        LEA.L   PAT_B6DB(PC),A0                 | A0 = third pattern (B6DB = 1011_0110...)
        LEA.L   PATTERN_TESTS_DONE(PC),A5       | return to PATTERN_TESTS_DONE after final pass
        BRA.B   PATTERN_FILL_VERIFY             | fill/verify RAM with pattern PAT_B6DB

| ----------------------------------------------------------
|
| PATTERN_TESTS_DONE - all pattern tests complete, assemble final results
|
| Called during boot.
PATTERN_TESTS_DONE:
        MOVE.L  A2,A5                           | A5 = top of verified RAM (for BootPart2)
        MOVEQ.L #0x0,D1                         | clear D1 high word
        MOVE    D0,D1                           | D1 low = accumulated error bits (low word)
        SWAP    D0                              | D0 = high word of error accumulator
        OR      D0,D1                           | D1 = combined error (zero if all patterns passed)
MEMTEST_RETURN:
        MOVE.L  A5,D0                           | D0 = RAM end address (return value for boot code)
        TST     D1                              | set Z flag: Z=1 all tests passed, Z=0 failure
        JMP     (A6)                            | return to boot code (BOOT_MEMTEST_RET in vectors.s)

| PATTERN_FILL_VERIFY - pattern fill/verify subroutine
|
| Fills verified RAM (A3..A2) with a repeating 12-byte pattern from (A0),
| then reads back and XORs against expected values. Any mismatched bits
| are accumulated into D0 (OR'd in). Uses MOVEM for fast 12-byte-at-a-time
| memory access (3 longwords = 12 bytes per iteration).
|
| Entry: A0 = pattern data (12 bytes), A3 = RAM base, A2 = RAM end
| A5 = return address, D0 = running error accumulator
| Exit: D0 = updated error accumulator (0 = no new errors)
| Called during boot.
PATTERN_FILL_VERIFY:
        MOVE.L  A2,D1                           | D1 = RAM end address
        SUB.L   A3,D1                           | D1 = total RAM size in bytes
        MOVE.L  D1,D2                           | D2 = RAM size (copy for high-word extract)
        CLR     D2                              | clear low word of D2
        SWAP    D2                              | D2 = high word of RAM size (size >> 16)
        MOVEQ.L #0x0,D3                         | D3 = 0
        MOVE    D1,D3                           | D3 = low word of RAM size
        ADD.L   D3,D2                           | D2 = (size>>16) + (size & 0xFFFF) for modulo calc
        DIVU    #0x3,D2                         | D2 = sum / 3 (remainder in high word)
        CLR     D2                              | discard quotient
        SWAP    D2                              | D2 = remainder (size mod 3, in bytes)
        MOVE.L  A2,D3                           | D3 = RAM end address
        SUBQ.L  #0x2,D2                         | D2 = remainder - 2 (alignment adjustment)
        ADD.L   D2,D2                           | D2 *= 2 (convert to byte offset for fill padding)
        ADD.L   D2,D3                           | D3 = adjusted end pointer for descending fill
        ADD.L   D2,D1                           | D1 = adjusted total byte count
        MOVE    D1,D7                           | D7 low = low word of adjusted count
        CLR     D1                              | clear low word
        SWAP    D1                              | D1 = high word of adjusted count
        DIVU    #0xC,D1                         | D1 = high_count / 12 (12 bytes per MOVEM)
        SWAP    D1                              | D1 = remainder of high_count / 12
        SWAP    D7                              | position low word count into high word
        MOVE    D1,D7                           | D7.hi = remainder, D7.lo preserved
        SWAP    D7                              | D7 = combined iteration count
        DIVU    #0xC,D7                         | D7 = total iterations (full count / 12)
        MOVE    D7,D1                           | D1 = iteration count for fill loop
        MOVE.L  D1,D7                           | D7 = save iteration count for verify loop
        LSR.L   #0x1,D1                         | D1 = half iterations (fill from both ends)
        MOVE.L  D3,A1                           | A1 = adjusted end ptr (descending fill start)
        MOVEM.L (A0),D2-D6                      | load 20 bytes of pattern into D2-D6
        MOVE.L  A3,A0                           | A0 = RAM base (ascending fill start)
| Fill loop: writes pattern from both ends simultaneously
| A0 ascends writing D2-D4 (12 bytes), A1 descends writing D4-D6 (12 bytes)
FILL_LOOP:
        MOVEM.L D2-D4,(A0)                      | write 12 pattern bytes ascending from A0
        ADDA    #0xC,A0                         | advance ascending pointer by 12 bytes
        MOVEM.L D4-D6,-(A1)                     | write 12 pattern bytes descending from A1
        SUBQ.L  #0x1,D1                         | decrement fill iteration counter
        BPL.B   FILL_LOOP                       | continue until both halves meet in middle
| Verify loop: reads back 12 bytes at a time, XORs with expected pattern
        MOVE.L  A3,A0                           | A0 = RAM base (verify from start)
        MOVE.L  D7,D1                           | D1 = total iteration count for verify
VERIFY_LOOP:
        MOVEM.L (A0)+,D5-D7                     | read 12 bytes of RAM into D5-D7
        EOR.L   D2,D5                           | XOR with expected pattern word 1 (zero if match)
        EOR.L   D3,D6                           | XOR with expected pattern word 2
        EOR.L   D4,D7                           | XOR with expected pattern word 3
        OR.L    D5,D6                           | combine mismatched bits from words 1-2
        OR.L    D6,D7                           | combine all mismatched bits
        OR.L    D7,D0                           | accumulate into running error register
        SUBQ.L  #0x1,D1                         | decrement verify iteration counter
        BGT.B   VERIFY_LOOP                     | continue until all RAM verified
        JMP     (A5)                            | return to pattern test chain

| ----------------------------------------------------------
|
| PAT_DB6D/PAT_B6DB/PAT_6DB6 - three complementary DRAM test patterns
|
| Each pattern uses the repeating 3-bit sequence (110, 101, 011) shifted
| by one bit, so together all three patterns test every bit as both 0 and 1.
| PAT_DB6D (2 bytes) and PAT_B6DB (2 bytes) overlap into PAT_6DB6 (20 bytes) which holds
| 5 longwords loaded by MOVEM into D2-D6 for the fill subroutine.
PAT_DB6D:
  .byte 0xDB,0x6D                               | pattern 1: 1101_1011 0110_1101

PAT_B6DB:
  .byte 0xB6,0xDB                               | pattern 3: 1011_0110 1101_1011

PAT_6DB6:
  .byte 0x6D,0xB6,0xDB,0x6D,0xB6,0xDB           | pattern 2: 0110_1101... (word 1)
  .byte 0x6D,0xB6,0xDB,0x6D,0xB6,0xDB           | pattern 2 repeated (word 2)
  .byte 0x6D,0xB6,0xDB,0x6D,0xB6,0xDB           | pattern 2 repeated (word 3)
  .byte 0x6D,0xB6                               | pattern 2 tail (fills D6 high)
