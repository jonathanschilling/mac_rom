| MicroBug -- built-in minimal ROM debugger (Plus-only)
|
| Entered from IconDispatch/SysErr2 in debugger.s when no external
| debugger (MacsBug) is installed. Provides a hex expression parser
| and a small command set:
|
| G   - resume (go)
| DM  - display memory
| FS  - fill memory (store)
| TD  - toggle display radix
| DAt - display A-reg
| AAt - show all A-regs
| PC  - display/set PC
| SR  - display/set SR
|
| Uses the serial port for I/O (selectable via PRAM: modem = 1,
| printer = 2). Saved CPU state lives in SERegs at 0x3FFC80;
| command buffer and MicroBug state live at 0x3FFCD4..0x3FFCFC.
|
| This file is Plus-only -- the classic (128K/512K) ROM has no
| interactive ROM debugger. Phase 10A stopped splitting debugger.s
| here because everything preceding MicroBug in ROM (exception
| machinery, IconDispatch/SysErr2, AllocFakeRgns + INSTALL_INF_RGN,
| SysBeep, DSErrorHandler, DSERR_*, LOOKUP_*) is physically
| contiguous and moving it to sad_mac.s/font_mgr.s to match classic
| would shift ROM bytes.
|
| References:
| Technical Note TN1136: MicroBug, The ROM Debugger

| ----------------------------------------------------------
|
| MICROBUG_ENTRY - MicroBug interactive command loop entry
|
| Sets up the debugger display window and enters the main
| command input/dispatch loop. Uses the DS error handler's
| temporary GrafPort for drawing.
MICROBUG_ENTRY:
        ADDQ.L  #0x2,SP                         | discard error code from stack
        LEA.L   (DSAlertRect).w,A0              | point to alert rect
        BSR     SET_DEFAULT_RECT                | set up default rect and draw frame
        MOVE.L  #0x460026,-(SP)                 | move port origin to (38,70)
        _MovePortTo                             | position within debugger window
        BSR     COPY_ALERT_RECT                 | copy and offset alert rect
        SUBA    #0x10,SP                        | allocate 16 bytes for erase rect
        CLR     D7                              | D7 = 0 (no previous command)
        CLR.L   (0x3FFCF8).l                    | clear dot address (".")
        CLR.L   (0x3FFCFC).l                    | clear DM continuation address
| ----------------------------------------------------------
|
| MICROBUG_PROMPT - MicroBug prompt: clear input line, draw ">" prompt
|
MICROBUG_PROMPT:
        MOVE.L  #0x1101B0,-(SP)                 | erase rect: top=17, left=0
        CLR.L   -(SP)                           | bottom=0, right=432 (full width)
        BSR     ERASE_STACK_RECT                | erase the input/output area
        LEA.L   (0x3FFCF6).l,A6                 | A6 = end of input buffer
        MOVEQ.L #0x0,D6                         | D6 = 0 (chars remaining counter)
MICROBUG_FILL_BUF:
        MOVE    #0x20,-(A6)                     | fill buffer with spaces (backwards)
        ADDQ.W  #0x2,D6                         | count bytes filled
        CMPI    #0x22,D6                        | filled 34 bytes (17 words)?
        BNE.B   MICROBUG_FILL_BUF               | no - keep filling
        MOVE.L  A6,A4                           | A4 = start of input buffer
        MOVE.L  #0xF000A,-(SP)                  | pen position: Y=15, X=10
        _MoveTo                                 | set pen for prompt character
        MOVEQ.L #0x3E,D0                        | '>' ASCII = 0x3E
        MOVE    D0,-(SP)                        | push char for DrawChar
        _DrawChar                               | draw the ">" prompt
| ----------------------------------------------------------
|
| MICROBUG_KEY_LOOP - keyboard input loop: read characters into buffer
|
| Polls for keyboard events, converts lowercase to uppercase,
| handles Return (execute), Backspace (delete), and printable chars.
| Input buffer: A4=start, A6=current write position.
| D6 = remaining character slots.
MICROBUG_KEY_LOOP:
        MOVE.L  A7,A0                           | A0 = event record (on stack)
        MOVEQ.L #0x8,D0                         | event mask: keyDown + autoKey
        _GetOSEvent                             | poll for keyboard event
        BNE.B   MICROBUG_KEY_LOOP               | no event - keep polling
        MOVE.L  0x2(SP),D0                      | D0 = event message (char in low byte)
        BCLR    #0x7,D0                         | strip high bit (key-up flag)
        CMPI.B  #0x61,D0                        | >= 'a' (lowercase)?
        BLT.B   MICROBUG_CHECK_KEY              | no - leave as-is
        BCLR    #0x5,D0                         | convert lowercase to uppercase
MICROBUG_CHECK_KEY:
        CMPI.B  #0xD,D0                         | Return key?
        BEQ.B   MICROBUG_EXEC_CMD               | yes - execute command
        CMPI.B  #0x8,D0                         | Backspace key?
        BNE.B   MICROBUG_STORE_CH               | no - handle as printable char
        CMPA.L  A6,A4                           | buffer empty (A4 == A6)?
        BEQ.B   MICROBUG_KEY_LOOP               | yes - ignore backspace
        ADDQ.W  #0x1,D6                         | restore one character slot
        SUBQ.L  #0x1,A6                         | move write pointer back one char
        SUBQ.L  #0x4,SP                         | allocate temp Point on stack
        MOVE.L  A7,-(SP)                        | push ptr for GetPen
        _GetPen                                 | get current pen position
        MOVE.L  (SP),-(SP)                      | duplicate pen pos for erase rect
        SUBQ.L  #0x2,SP                         | make room for CharWidth result
        MOVE.B  (A6),D0                         | D0 = character being deleted
        MOVE    D0,-(SP)                        | push char for CharWidth
        _CharWidth                              | get pixel width of deleted char
        MOVE    (SP)+,D3                        | D3 = char width in pixels
        SUB     D3,0x2(SP)                      | adjust rect left edge back by width
        CLR     (SP)                            | rect top = 0
        MOVE.L  A7,-(SP)                        | push erase rect ptr
        CLR     -(SP)                           | dv = 0
        MOVE    #0x2,-(SP)                      | dh = 2 (small right margin)
        _OffsetRect                             | adjust erase rect
        BSR     ERASE_STACK_RECT                | erase the character area
        MOVE    D3,-(SP)                        | push char width (negated below)
        NEG     (SP)                            | negate: move pen left
        CLR     -(SP)                           | dv = 0
        _Move                                   | back up pen position
        BRA.B   MICROBUG_KEY_LOOP               | continue input loop

| ----------------------------------------------------------
|
| MICROBUG_STORE_CH - store printable character in buffer and echo it
|
MICROBUG_STORE_CH:
        TST     D6                              | buffer full (D6 = 0)?
        BEQ.B   MICROBUG_KEY_LOOP               | yes - ignore character
        SUBQ.W  #0x1,D6                         | consume one character slot
        MOVE.B  D0,(A6)+                        | store char in buffer, advance ptr
        MOVE    D0,-(SP)                        | push char for DrawChar
        _DrawChar                               | echo character to screen
        BRA.B   MICROBUG_KEY_LOOP               | continue input loop

| ----------------------------------------------------------
|
| MICROBUG_EXEC_CMD - Return pressed: parse and dispatch command
|
| If input is empty, re-submit the previous command (D7).
| Otherwise read the first two chars as command code and
| look up in DT_DbgCmdTab for dispatch.
MICROBUG_EXEC_CMD:
        CMPA.L  A4,A6                           | empty input (A4 == A6)?
        BNE.B   MICROBUG_PARSE_CMD              | no - parse new command
        MOVE    D7,(A6)+                        | yes - repeat last command word
MICROBUG_PARSE_CMD:
        MOVE    (A4)+,D7                        | D7 = first two chars of input (cmd)
        LEA.L   DT_DbgCmdTab(PC),A0             | A0 = command dispatch table
MICROBUG_CMD_LOOP:
        MOVE    (A0)+,D0                        | D0 = table entry: command code
        BMI.B   MICROBUG_CMD_DONE               | 0xFFFF = end of table sentinel
        MOVE    (A0)+,D2                        | D2 = handler offset from table base
        CMPI.B  #0x40,D0                        | is low byte '@'? (register cmd)
        BNE.B   MICROBUG_CMD_CMP                | no - exact two-char match
        MOVE.B  D7,D0                           | D0 = 2nd char of user input
        CMPI.B  #0x30,D0                        | < '0'?
        BMI.B   MICROBUG_CMD_LOOP               | yes - not a digit, skip entry
        CMPI.B  #0x37,D0                        | > '7'?
        BGT.B   MICROBUG_CMD_LOOP               | yes - not valid register 0-7, skip
MICROBUG_CMD_CMP:
        CMP     D0,D7                           | command matches table entry?
        BNE.B   MICROBUG_CMD_LOOP               | no - try next entry
        LEA.L   DT_DbgCmdTab(PC),A0             | A0 = table base for offset calc
        JSR     0x0(A0,D2.W)                    | call handler at table + offset
MICROBUG_CMD_DONE:
        BRA     MICROBUG_PROMPT                 | loop back to prompt

| ----------------------------------------------------------
|
| DT_DbgCmdTab - MicroBug command dispatch table
|
| Each entry: 2-byte command code, 2-byte offset from table base.
| '@' (0x40) in low byte = register command (D0-D7 or A0-A7).
| "G " = Go, "DM" = Dump Memory, "SM" = Set Memory,
| "TD" = Total Display, "D@" = Data reg, "A@" = Addr reg,
| "PC" = Program Counter, "SR" = Status Register.
DT_DbgCmdTab:
  .byte 0x47,0x20,0x00,0x22,0x44,0x4D
  .byte 0x00,0x46,0x53,0x4D,0x00,0xC6
  .byte 0x54,0x44,0x00,0xF2,0x44,0x40
  .byte 0x01,0x00,0x41,0x40,0x01,0x08
  .byte 0x50,0x43,0x01,0x10,0x53,0x52
  .byte 0x01,0x18,0xFF,0xFF

| ----------------------------------------------------------
|
| DbgCmd_G - Go command: resume execution at address
|
| "G addr" resumes at addr. "G" alone resumes from saved PC.
DbgCmd_G:
        BSR     EVAL_EXPR                       | parse address expression
        BEQ.B   DBGCMD_G_RESUME                 | no argument - resume from saved PC
        MOVE.L  D0,-(SP)                        | push target address
        BSR     INSTALL_INF_RGN                 | restore region data
        RTS                                     | jump to target address

| ----------------------------------------------------------
|
| DBGCMD_G_RESUME - G with no argument: resume from exception point
|
DBGCMD_G_RESUME:
        ADDA    #0x14,SP                        | deallocate debugger stack frame
        CLR.B   (DSWndUpdate).w                 | clear DS window update flag
        BRA     DSERR_RESUME                    | return 0 to resume execution

| ----------------------------------------------------------
|
| ERASE_STACK_RECT - erase rectangle area on stack
|
| The caller pushes a rect (8 bytes) before calling. ERASE_STACK_RECT pops
| the return address, calls EraseRect on the stacked rect,
| then cleans up and jumps back to the caller.
ERASE_STACK_RECT:
        MOVE.L  (SP)+,A2                        | save return address
        MOVE.L  A7,-(SP)                        | push rect ptr (stack top = rect)
        _EraseRect                              | erase the rectangular area
        ADDQ.L  #0x8,SP                         | pop the 8-byte rect from stack
        JMP     (A2)                            | return to caller

| ----------------------------------------------------------
|
| DbgCmd_DM - Dump Memory command
|
| Displays 6 rows of 8 words (96 bytes) starting at the
| parsed address or the DM continuation address.
| Format: address followed by 8 hex words per line.
DbgCmd_DM:
        MOVE.L  #0x7001B0,-(SP)                 | erase rect: top=112, left=0
        CLR.L   -(SP)                           | bottom=0, right=432
        BSR.B   ERASE_STACK_RECT                | erase output area
        BSR     PARSE_ADDR_OR_CONT              | parse addr or use continuation
        BCLR    #0x0,D0                         | force even address
        MOVE.L  D0,A3                           | A3 = memory read pointer
        MOVE.L  D0,(0x3FFCF8).l                 | set dot address for expressions
        MOVEQ.L #0x5,D6                         | D6 = 5 (6 rows, counted 5..0)
        MOVEQ.L #0xF,D5                         | D5 = initial Y position (15)
DM_ROW_LOOP:
        ADDI    #0xF,D5                         | advance Y by 15 pixels per row
        MOVE    #0xA,-(SP)                      | X = 10 (left margin)
        MOVE    D5,-(SP)                        | push Y position
        _MoveTo                                 | position pen for address column
        MOVE.L  A3,D0                           | D0 = current address
        BSR.B   PRINT_HEX_LONG                  | print 8-digit hex address
        MOVEQ.L #0x7,D4                         | D4 = 7 (8 words per row, counted 7..0)
        MOVEQ.L #0x23,D3                        | D3 = initial X for data columns (35)
DM_WORD_LOOP:
        ADDI    #0x2D,D3                        | advance X by 45 pixels per word
        MOVE    D3,-(SP)                        | push X position
        MOVE    D5,-(SP)                        | push Y position
        _MoveTo                                 | position pen for hex word
        MOVE    (A3)+,D0                        | read next memory word, advance ptr
        BSR.B   PRINT_HEX_WORD                  | print 4-digit hex word
        DBF     D4,DM_WORD_LOOP                 | loop for 8 words per row
        DBF     D6,DM_ROW_LOOP                  | loop for 6 rows
        MOVE.L  A3,(0x3FFCFC).l                 | save continuation address for next DM
        RTS                                     | return to command prompt

| ----------------------------------------------------------
|
| PRINT_HEX_LONG - print 32-bit hex value (8 digits)
|
| Prints D0 as 8 hex digits by printing high word then low word.
PRINT_HEX_LONG:
        SWAP    D0                              | get high word of D0
        BSR.B   PRINT_HEX_BYTE                  | print high word as 2 hex digits
        SWAP    D0                              | restore low word
| ----------------------------------------------------------
|
| PRINT_HEX_WORD - print 16-bit hex value (4 digits)
|
PRINT_HEX_WORD:
        MOVE    D0,-(SP)                        | save low byte
        ROXR    #0x8,D0                         | shift high byte to low position
        BSR.B   PRINT_HEX_BYTE                  | print high byte as 2 hex digits
        MOVE    (SP)+,D0                        | restore original value
| ----------------------------------------------------------
|
| PRINT_HEX_BYTE - print 8-bit hex value (2 digits)
|
PRINT_HEX_BYTE:
        MOVE    D0,-(SP)                        | save value
        ROR     #0x4,D0                         | rotate high nibble to low position
        BSR.B   PRINT_HEX_NIBBLE                | print high nibble
        MOVE    (SP)+,D0                        | restore value
| ----------------------------------------------------------
|
| PRINT_HEX_NIBBLE - print single hex nibble (low 4 bits of D0)
|
PRINT_HEX_NIBBLE:
        ANDI.B  #0xF,D0                         | isolate low nibble
        ORI.B   #0x30,D0                        | convert to ASCII '0'-'9'
        CMPI.B  #0x39,D0                        | > '9'?
        BLE.B   HEX_DIGIT_OK                    | no - digit is correct
        ADDQ.W  #0x7,D0                         | yes - adjust to 'A'-'F'
HEX_DIGIT_OK:
        MOVE.L  D0,-(SP)                        | save D0 (DrawChar clobbers it)
        MOVE    D0,-(SP)                        | push char for DrawChar
        _DrawChar                               | draw the hex digit
        MOVE.L  (SP)+,D0                        | restore D0
        RTS                                     | return from hex digit printing

| ----------------------------------------------------------
|
| DbgCmd_FS - SM (Set Memory) command
|
| "SM addr expr..." stores expression values into memory at
| addr, sizing each store (byte/word/long) based on the
| expression size (D1 from EVAL_EXPR). After all values are written,
| displays the memory via DM.
| Note: command code is "SM" but label says FS (First Set?).
DbgCmd_FS:
        BSR     PARSE_ADDR_OR_CONT              | parse start address (or use cont.)
        MOVE.L  D0,A1                           | A1 = target memory write pointer
        LEA.L   (0x3FFCF8).l,A0                 | A0 = dot address storage
        MOVE.L  D0,(A0)+                        | set dot address to start addr
        MOVE.L  D0,(A0)+                        | set DM continuation addr too
        MOVE    #0x444D,D7                      | D7 = "DM" - repeat cmd shows dump
SM_PARSE_LOOP:
        BSR     EVAL_EXPR                       | parse next expression value
        BEQ     DbgCmd_DM                       | no more values - show memory dump
        MOVE.L  A1,A2                           | A2 = write position for this value
SM_STORE_LOOP:
        MOVE.B  D0,-0x1(A2,D1.W)                | store byte at big-endian position
        ASR.L   #0x8,D0                         | shift next byte down
        ADDQ.L  #0x1,A1                         | advance write pointer
        SUBQ.L  #0x1,D1                         | decrement size counter
        BNE.B   SM_STORE_LOOP                   | more bytes to store
        BRA.B   SM_PARSE_LOOP                   | parse next expression

| ----------------------------------------------------------
|
| DbgCmd_TD - Total Display: dump all saved registers
|
| Sets DM continuation to SEVarBase (0x3FFC80) so that DM
| displays the 16 saved registers (D0-D7, A0-A7) plus SP/PC/SR.
DbgCmd_TD:
        MOVE.L  #0x3FFC80,(0x3FFCFC).l          | set continuation to reg save area

        BRA     DbgCmd_DM                       | display as hex dump

| ----------------------------------------------------------
|
| DbgCmd_DAt - Dx command: display/set data register
|
| "Dx" displays saved data register x. "Dx expr" sets it.
| Register number extracted from second command char.
DbgCmd_DAt:
        LEA.L   (0x3FFC80).l,A3                 | A3 = saved D0 in SEVarBase
        BRA.B   DBGREG_PARSE_NUM                | parse register number and value

| ----------------------------------------------------------
|
| DbgCmd_AAt - Ax command: display/set address register
|
| "Ax" displays saved address register x. "Ax expr" sets it.
DbgCmd_AAt:
        LEA.L   (0x3FFCA0).l,A3                 | A3 = saved A0 in SEVarBase
        BRA.B   DBGREG_PARSE_NUM                | parse register number and value

| ----------------------------------------------------------
|
| DbgCmd_PC - PC command: display/set program counter
|
| "PC" displays saved PC. "PC expr" sets it.
DbgCmd_PC:
        LEA.L   (0x3FFCC0).l,A3                 | A3 = saved PC (MacsBugPC)
        BRA.B   DBGREG_PARSE_VAL                | parse optional value

| ----------------------------------------------------------
|
| DbgCmd_SR - SR command: display/set status register
|
| "SR" displays saved SR. "SR expr" sets it (word-sized).
DbgCmd_SR:
        LEA.L   (0x3FFCC4).l,A3                 | A3 = saved SR (MacsBugSR)
        BSR.B   EVAL_EXPR                       | parse expression
        BEQ.B   DBGREG_SHOW_WORD                | no arg - display SR
        MOVE    D0,(A3)                         | store new SR value (word)
        RTS                                     | return to command prompt

| ----------------------------------------------------------
|
| DBGREG_PARSE_NUM - parse register number and optional value for Dx/Ax
|
DBGREG_PARSE_NUM:
        BSR.B   ASCII_TO_NIBBLE                 | convert 2nd char to register number
        LSL.L   #0x2,D0                         | multiply by 4 (long-sized regs)
        ADDA.L  D0,A3                           | A3 = &saved register[n]
DBGREG_PARSE_VAL:
        BSR.B   EVAL_EXPR                       | parse optional value expression
        BEQ.B   DBGREG_DISPLAY                  | no arg - display the register
        MOVE.L  D0,(A3)                         | store new register value (long)
        RTS                                     | return to command prompt

| ----------------------------------------------------------
|
| DBGREG_SHOW_WORD - SR display: flag for word-sized display
|
DBGREG_SHOW_WORD:
        MOVEQ.L #-0x1,D6                        | D6 = -1: display as word (not long)
| ----------------------------------------------------------
|
| DBGREG_DISPLAY - display register value from save area
|
DBGREG_DISPLAY:
        MOVE.L  #0x7001B0,-(SP)                 | erase rect: top=112, left=0
        CLR.L   -(SP)                           | bottom=0, right=432
        BSR     ERASE_STACK_RECT                | erase output area
        MOVE.L  #0x300010,-(SP)                 | pen position: Y=48, X=16
        _MoveTo                                 | position pen for value display
        MOVE    (A3)+,D0                        | read high word of saved register
        TST     D6                              | word-only display mode (SR)?
        BNE.B   DBGREG_PRINT_LOW                | yes - skip high word display
        BSR     PRINT_HEX_WORD                  | print high word as 4 hex digits
        MOVE    (A3)+,D0                        | read low word
DBGREG_PRINT_LOW:
        BSR     PRINT_HEX_WORD                  | print (low) word as 4 hex digits
        RTS                                     | return after printing register

| ----------------------------------------------------------
|
| ASCII_TO_NIBBLE - convert ASCII hex character in D0 to 0-15
|
| Same algorithm as TN1136's StringToNumber: if > '9',
| subtract 7 to map 'A'-'F' to 10-15, then mask low nibble.
ASCII_TO_NIBBLE:
        ANDI.L  #0xFF,D0                        | isolate ASCII byte
        CMPI.B  #0x39,D0                        | > '9'?
        BLE.B   NIBBLE_IS_DIGIT                 | no - '0'-'9' range
        SUBQ.B  #0x7,D0                         | adjust 'A'-'F' to 0x3A-0x3F
NIBBLE_IS_DIGIT:
        ANDI.B  #0xF,D0                         | mask to low nibble (0-15)
        RTS                                     | return with nibble in D0

| ----------------------------------------------------------
|
| PARSE_ADDR_OR_CONT - parse address, defaulting to DM continuation address
|
| If the user typed an expression, returns it in D0.
| Otherwise returns the DM continuation address (for "DM" alone).
PARSE_ADDR_OR_CONT:
        BSR.B   EVAL_EXPR                       | try to parse expression
        BNE.B   PARSE_ADDR_RTS                  | got one - return it in D0
        MOVE.L  (0x3FFCFC).l,D0                 | no arg - use continuation address
PARSE_ADDR_RTS:
        RTS                                     | return parsed or continuation addr

| ----------------------------------------------------------
|
| EVAL_EXPR - MicroBug expression evaluator
|
| Parses the input buffer (A4..A6) and evaluates the expression.
| Returns: D0 = value, D1 = expression size (1/2/4 bytes),
| Z=1 if no expression found, Z=0 if valid.
|
| Supports: hex numbers, "." (dot address), "@" (indirect),
| "+" and "-" operators, RAx/RDx (register), PC (program counter).
| See TN1136 for the full expression grammar.
|
| Registers:
| D4 = running accumulator (sum of terms)
| D6 = max expression size seen
| D5 = current term's digit count (determines size)
| D3 = "@" indirection count
| D1 = current term value being built
| 0x3FFCF6 = negate flag (toggled by "-" prefix)
| Called by: DbgCmd_G, SM_PARSE_LOOP, DbgCmd_SR, DBGREG_PARSE_VAL, PARSE_ADDR_OR_CONT
EVAL_EXPR:
        MOVEQ.L #0x0,D4                         | D4 = 0: accumulated result
        MOVEQ.L #0x0,D6                         | D6 = 0: max expression size
| ----------------------------------------------------------
|
| EXPR_NEW_TERM - start parsing a new term in the expression
|
EXPR_NEW_TERM:
        MOVEQ.L #0x0,D5                         | D5 = 0: digit count for this term
        CLR     (0x3FFCF6).l                    | clear negate flag
        MOVEQ.L #0x0,D3                         | D3 = 0: indirection count (@)
        MOVEQ.L #0x0,D0                         | clear working char
        MOVEQ.L #0x0,D1                         | D1 = 0: current term value
| ----------------------------------------------------------
|
| EXPR_SKIP_SPACE - skip whitespace and control chars in input
|
EXPR_SKIP_SPACE:
        CMPA.L  A6,A4                           | past end of input?
        BGE     EXPR_FINALIZE                   | yes - finalize current term
EXPR_SCAN_PREFIX:
        MOVE.B  (A4)+,D0                        | read next input character
        CMPI.B  #0x20,D0                        | space or control char?
        BLE.B   EXPR_SKIP_SPACE                 | yes - skip it
        CMPI.B  #0x40,D0                        | '@' = indirection operator?
        BNE.B   EXPR_CHECK_OP                   | no - check for +/-
        ADDQ.W  #0x1,D3                         | increment indirection depth
        BRA.B   EXPR_SCAN_PREFIX                | continue scanning prefixes

| ----------------------------------------------------------
|
| EXPR_CHECK_OP - check for +/- operators between terms
|
EXPR_CHECK_OP:
        CMPI.B  #0x2B,D0                        | '+' addition operator?
        BEQ.B   EXPR_SCAN_PREFIX                | yes - skip (addition is default)
        CMPI.B  #0x2D,D0                        | '-' negation/subtraction?
        BNE.B   EXPR_CHECK_HEX                  | no - must be a value token
        NOT.B   (0x3FFCF6).l                    | toggle negate flag for this term
        BRA.B   EXPR_SCAN_PREFIX                | continue scanning prefixes

| ----------------------------------------------------------
|
| EXPR_CHECK_HEX - check for '$' hex prefix or bare hex number
|
EXPR_CHECK_HEX:
        CMPI.B  #0x24,D0                        | '$' explicit hex prefix?
        BNE     EXPR_CHECK_DOT                  | no - check for '.', 'PC', 'RA', 'RD'
        MOVEQ.L #0x0,D0                         | clear for hex digit accumulation
        MOVE.B  (A4)+,D0                        | read first hex digit after '$'
| ----------------------------------------------------------
|
| EXPR_HEX_LOOP - hex digit accumulation loop
|
| Converts each ASCII char to 0-15 via ASCII_TO_NIBBLE (forgiving: any
| char that isn't a digit just contributes its low nibble,
| which is why "G FINDER" evaluates to an odd address).
EXPR_HEX_LOOP:
        BSR.B   ASCII_TO_NIBBLE                 | convert ASCII to 0-15 nibble
        ADDQ.W  #0x1,D5                         | count hex digits (determines size)
        LSL.L   #0x4,D1                         | shift accumulator left 4 bits
        ADD.L   D0,D1                           | add new nibble
        CMPA.L  A6,A4                           | past end of input?
        BGE.B   EXPR_FINALIZE                   | yes - finalize this term
        MOVE.B  (A4)+,D0                        | read next char
        CMPI.B  #0x30,D0                        | >= '0' (still a hex digit)?
        BGE.B   EXPR_HEX_LOOP                   | yes - accumulate it
| ----------------------------------------------------------
|
| EXPR_FINALIZE - finalize current term: apply indirection and negate
|
EXPR_FINALIZE:
        TST     D3                              | any '@' indirection pending?
        BEQ.B   EXPR_CHECK_NEG                  | no - skip dereference
        MOVEQ.L #0x8,D5                         | indirection result is 4 bytes (size=8 digits)
EXPR_DEREF_LOOP:
        BClr    #0x0,D1                         | force even address for dereference
        MOVE.L  D1,A0                           | A0 = address to read
        MOVE.L  (A0),D1                         | D1 = long at that address
        SUBQ.W  #0x1,D3                         | decrement indirection count
        BNE.B   EXPR_DEREF_LOOP                 | more levels - keep dereferencing
EXPR_CHECK_NEG:
        TST.B   (0x3FFCF6).l                    | negate flag set?
        BEQ.B   EXPR_ACCUMULATE                 | no - value is positive
        NEG.L   D1                              | negate the term value
EXPR_ACCUMULATE:
        ADD.L   D1,D4                           | accumulate into running total
        ADDQ.W  #0x1,D5                         | round digit count up
        LSR     #0x1,D5                         | D5 = byte count (digits/2)
        CMPI    #0x4,D5                         | cap at 4 bytes max
        BLE.B   EXPR_CHECK_SIZE                 | <= 4: skip clamping
        MOVEQ.L #0x4,D5                         | clamp size to 4
EXPR_CHECK_SIZE:
        CMP     D6,D5                           | larger than max seen?
        BLE.B   EXPR_CHECK_NEXT                 | no - keep current max
        MOVE    D5,D6                           | yes - update max expression size
EXPR_CHECK_NEXT:
        CMPI.B  #0x2B,D0                        | '+' follows this term?
        BEQ.B   EXPR_NEXT_TERM                  | yes - parse next term
        CMPI.B  #0x2D,D0                        | '-' follows this term?
        BNE.B   EXPR_RETURN                     | no - expression is complete
EXPR_NEXT_TERM:
        MOVE.B  D0,-(A4)                        | push +/- back for next term parsing
        BRA     EXPR_NEW_TERM                   | parse next term

| ----------------------------------------------------------
|
| EXPR_RETURN - expression complete: return value and size
|
EXPR_RETURN:
        MOVE.L  D4,D0                           | D0 = expression value
        MOVE.L  D6,D1                           | D1 = expression size (1/2/4 bytes)
        RTS                                     | return from expression parser

| ----------------------------------------------------------
|
| EXPR_CHECK_DOT - check for '.' (dot address) or register tokens
|
EXPR_CHECK_DOT:
        CMPI.B  #0x2E,D0                        | '.' dot address?
        BNE.B   EXPR_CHECK_PC                   | no - check for PC/RA/RD
        MOVE.L  (0x3FFCF8).l,D1                 | D1 = dot address value
        MOVEQ.L #0x1,D2                         | skip 1 char (the '.' itself)
| ----------------------------------------------------------
|
| EXPR_TOKEN_DONE - common path for '.', PC, and register tokens
|
| D1 = value, D2 = chars to consume from input buffer.
EXPR_TOKEN_DONE:
        MOVEQ.L #0x8,D5                         | size = 8 digits (4 bytes)
EXPR_SKIP_CHARS:
        MOVE.B  (A4)+,D0                        | consume trailing chars from token
        SUBQ.W  #0x1,D2                         | decrement chars to skip
        BNE.B   EXPR_SKIP_CHARS                 | more to skip
        BRA.B   EXPR_FINALIZE                   | finalize this term

| ----------------------------------------------------------
|
| EXPR_CHECK_PC - check for "PC" (program counter) token
|
EXPR_CHECK_PC:
        MOVE    D0,D2                           | D2 high byte = first char
        LSL     #0x8,D2                         | shift to make room for second char
        MOVE.B  (A4),D2                         | D2 = two-char token (e.g. "PC")
        CMPI    #0x5043,D2                      | "PC" ?
        BNE.B   EXPR_CHECK_REG                  | no - check for 'R' register prefix
        MOVE.L  (0x3FFCC0).l,D1                 | D1 = saved PC value (MacsBugPC)
        MOVEQ.L #0x2,D2                         | consume 2 chars ("PC")
        BRA.B   EXPR_TOKEN_DONE                 | finalize as 4-byte value

| ----------------------------------------------------------
|
| EXPR_CHECK_REG - check for "RAx" or "RDx" register tokens
|
EXPR_CHECK_REG:
        CMPI.B  #0x52,D0                        | first char 'R'?
        BNE     EXPR_HEX_LOOP                   | no - treat as bare hex digits
        CMPI.B  #0x41,D2                        | second char 'A' (address reg)?
        BNE.B   EXPR_CHECK_RD                   | no - check for 'D'
        LEA.L   (0x3FFCA0).l,A0                 | A0 = saved A registers base
| ----------------------------------------------------------
|
| EXPR_READ_REGNUM - read register number and fetch saved value
|
EXPR_READ_REGNUM:
        MOVEQ.L #0x0,D2                         | clear for register number
        MOVE.B  0x1(A4),D2                      | D2 = third char (register digit)
        SUBI    #0x30,D2                        | convert '0'-'7' to 0-7
        BMI     EXPR_HEX_LOOP                   | < 0: not a digit, treat as hex
        CMPI    #0x7,D2                         | > 7?
        BGT     EXPR_HEX_LOOP                   | yes: invalid register, treat as hex
        LSL     #0x2,D2                         | multiply by 4 (long-sized regs)
        MOVE.L  0x0(A0,D2.W),D1                 | D1 = saved register value
        MOVEQ.L #0x3,D2                         | consume 3 chars ("RAn" or "RDn")
        BRA.B   EXPR_TOKEN_DONE                 | finalize as 4-byte value

| ----------------------------------------------------------
|
| EXPR_CHECK_RD - check for "RDx" (data register) token
|
EXPR_CHECK_RD:
        CMPI.B  #0x44,D2                        | second char 'D' (data reg)?
        BNE     EXPR_HEX_LOOP                   | no - treat as bare hex digits
        LEA.L   (0x3FFC80).l,A0                 | A0 = saved D registers base
        BRA.B   EXPR_READ_REGNUM                | parse register number

| ----------------------------------------------------------
|
| SERIAL_DBG_ENTRY - serial debugger entry point (external debugger protocol)
|
| Called when MicroBug hands off to an external serial debugger.
| D0 encodes the operation: bit 15 set = specific request,
| bit 15 clear + D0=0 = auto-detect port.
SERIAL_DBG_ENTRY:
        BCLR    #0xF,D0                         | clear bit 15, test if it was set
        BNE.B   SERIAL_SEND_BLOCK               | was set - handle specific request
        TST     D0                              | D0 = 0? (auto-detect serial port)
        BNE     SERIAL_SEND_ACK                 | nonzero - use specified port
        MOVEQ.L #0x1,D0                         | default: port 1 (modem)
        BTST    #0x0,(KeyMap_7).w               | Shift key held?
        BEQ.B   SERIAL_USE_MODEM                | no - use modem port
        MOVEQ.L #0x2,D0                         | yes - use port 2 (printer)
SERIAL_USE_MODEM:
        BRA     SERIAL_INIT_PORT                | initialize serial port

| ----------------------------------------------------------
|
| SERIAL_SEND_CMD16 - send command byte D1 then 16-bit value D0 over serial
|
SERIAL_SEND_CMD16:
        MOVE    D0,-(SP)                        | save 16-bit value
        MOVE.B  D1,D0                           | D0 = command byte
        BSR     SERIAL_SEND_BYTE                | send command byte
        MOVE    (SP)+,D0                        | restore 16-bit value
        BRA     SERIAL_SEND_WORD                | send as 2 bytes (high then low)

| ----------------------------------------------------------
|
| SERIAL_SEND_BLOCK - send memory block over serial (response to request)
|
SERIAL_SEND_BLOCK:
        MOVE.L  A0,A2                           | A2 = memory block source address
        MOVEQ.L #0x2,D1                         | command byte 2 = "memory data"
        BSR.B   SERIAL_SEND_CMD16               | send cmd + 16-bit header
        MOVE    (0x3FFCCA).l,D2                 | D2 = byte count to send
        MOVE    D2,D0                           | send byte count as 16-bit value
        BSR     SERIAL_SEND_WORD                | transmit 16-bit byte count
SERIAL_SEND_LOOP:
        SUBQ.W  #0x1,D2                         | decrement bytes remaining
        BLT.B   SERIAL_CMD_LOOP                 | done - enter command receive loop
        MOVE.B  (A2)+,D0                        | read next byte from memory
        BSR     SERIAL_SEND_BYTE                | send byte over serial
        BRA.B   SERIAL_SEND_LOOP                | continue sending

| ----------------------------------------------------------
|
| SERIAL_SEND_ACK - send acknowledgment, enter serial command loop
|
SERIAL_SEND_ACK:
        MOVEQ.L #0x1,D1                         | command byte 1 = "ready/ack"
        BSR.B   SERIAL_SEND_CMD16               | send ack + status word
SERIAL_SET_ACTIVE:
        BSet    #0x6,(MacJmp).w                 | set bit 6: serial debugger active
| ----------------------------------------------------------
|
| SERIAL_CMD_LOOP - serial command receive loop
|
| Waits for a command byte from the remote debugger, dispatches
| via SERIAL_CMD_TABLE jump table. Commands: 0=nop, 1=ack, 2=send mem,
| 3=read mem, 4=write mem, 5=execute.
SERIAL_CMD_LOOP:
        MOVEQ.L #0x0,D1                         | D1 = 0: no timeout on receive
        BSR     SERIAL_RECV_BYTE                | receive command byte from serial
        LEA.L   SERIAL_CMD_TABLE(PC),A0         | A0 = serial command dispatch table
        ADD     D0,D0                           | word index into table
        ADDA    0x0(A0,D0.W),A0                 | A0 = handler address (PC-relative)
        JSR     (A0)                            | dispatch serial command
        BRA.B   SERIAL_CMD_LOOP                 | loop for next command

| ----------------------------------------------------------
|
| SERIAL_CMD_TABLE - serial command dispatch table (6 word offsets)
|
| Entries are PC-relative offsets from SERIAL_CMD_TABLE to handlers:
| [0] SERIAL_CMD_NOP (nop/ping), [1] SERIAL_CMD_READ (send memory block),
| [2] SERIAL_CMD_WRITE (write memory block), [3] SERIAL_CMD_EXEC (execute at addr),
| [4] SERIAL_CMD_WATCH (install A-trap watcher), [5] reserved
SERIAL_CMD_TABLE:
  .byte 0x00,0x0C,0x00,0x12,0x00,0x38
  .byte 0x00,0x52,0x00,0x5A,0x00,0x6C

| ----------------------------------------------------------
|
| SERIAL_CMD_NOP - serial NOP/ping: send 0 byte back
|
SERIAL_CMD_NOP:
        MOVEQ.L #0x0,D0                         | send 0 as acknowledgment
        BRA     SERIAL_SEND_BYTE                | transmit byte

| ----------------------------------------------------------
|
| SERIAL_CMD_READ - serial read memory: send block to remote debugger
|
| Receives: 4-byte address, 4-byte count from serial.
| Sends: command 3, count as long, then count bytes of memory.
SERIAL_CMD_READ:
        BSR     SERIAL_RECV_LONG                | receive 4-byte address
        MOVE.L  D0,A2                           | A2 = source address in memory
        BSR     SERIAL_RECV_LONG                | receive 4-byte byte count
        MOVE.L  D0,D2                           | D2 = bytes to send
        MOVEQ.L #0x3,D0                         | command 3 = "memory data response"
        BSR     SERIAL_SEND_BYTE                | send command byte
        MOVE.L  D2,D0                           | send byte count as 4-byte value
        BSR     SERIAL_SEND_LONG                | transmit long word
SERIAL_READ_LOOP:
        SUBQ.L  #0x1,D2                         | decrement bytes remaining
        BMI.B   SERIAL_READ_DONE                | all sent - done
        MOVE.B  (A2)+,D0                        | read next memory byte
        BSR     SERIAL_SEND_BYTE                | transmit byte
        BRA.B   SERIAL_READ_LOOP                | continue sending

| ----------------------------------------------------------
|
| SERIAL_READ_DONE - return from serial command handler
|
SERIAL_READ_DONE:
        RTS                                     | return to serial loop

| ----------------------------------------------------------
|
| SERIAL_CMD_WRITE - serial write memory: receive block from remote debugger
|
| Receives: 4-byte address, 4-byte count, then count data bytes.
| Writes received bytes into memory at the specified address.
SERIAL_CMD_WRITE:
        BSR     SERIAL_RECV_LONG                | receive 4-byte destination address
        MOVE.L  D0,A2                           | A2 = target address in memory
        BSR     SERIAL_RECV_LONG                | receive 4-byte byte count
        MOVE.L  D0,D2                           | D2 = bytes to receive
SERIAL_WRITE_LOOP:
        SUBQ.L  #0x1,D2                         | decrement bytes remaining
        BMI.B   SERIAL_WRITE_DONE               | all received - done
        BSR     SERIAL_RECV_BYTE                | receive one byte from serial
        MOVE.B  D0,(A2)+                        | store byte in memory, advance ptr
        BRA.B   SERIAL_WRITE_LOOP               | continue receiving

| ----------------------------------------------------------
|
| SERIAL_WRITE_DONE - return from serial write handler
|
SERIAL_WRITE_DONE:
        RTS                                     | return to serial loop

| ----------------------------------------------------------
|
| SERIAL_CMD_EXEC - serial execute: jump to address received from remote
|
SERIAL_CMD_EXEC:
        BSR     SERIAL_RECV_LONG                | receive 4-byte target address
        MOVE.L  D0,A0                           | A0 = execution address
        JMP     (A0)                            | jump to target (no return)

| ----------------------------------------------------------
|
| SERIAL_CMD_WATCH - install A-line trap watcher for serial debugger
|
| Saves the current A-line trap vector and installs TRAP_WATCHER as
| a filter that intercepts traps in a specified number range.
| The remote debugger sends the trap range to watch.
SERIAL_CMD_WATCH:
        LEA.L   TRAP_WATCHER(PC),A0             | A0 = trap watcher handler
        MOVE.L  (ATrapVector).w,(0x3FFCDA).l    | save original A-trap vector

        MOVE.L  A0,(ATrapVector).w              | install watcher as A-trap vector
        RTS                                     | return to serial loop

| ----------------------------------------------------------
|
| SERIAL_UNWATCH - uninstall trap watcher (called from TRAP_WATCHER filter)
|
SERIAL_UNWATCH:
        ADDQ.L  #0x4,SP                         | discard return address
        MOVEQ.L #0x0,D0                         | return 0 (success)
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| SCC_INIT_PARAMS - SCC initialization parameters for serial debugger
|
| 8 register/value pairs for Zilog 8530 SCC setup:
| WR4=0x4C (x16 clock, 2 stop bits), WR14=0x00 (BRG off),
| WR11=0x50 (RxC=BRG, TxC=BRG), WR12=0x0A (BRG low=10),
| WR13=0x00 (BRG high=0), WR14=0x01 (BRG enable),
| WR3=0xC1 (Rx 8-bit, enable), WR5=0x6A (Tx 8-bit, RTS, enable)
| Result: 9600 baud, 8N2
SCC_INIT_PARAMS:
  .byte 0x04,0x4C,0x0E,0x00,0x0B,0x50
  .byte 0x0C,0x0A,0x0D,0x00,0x0E,0x01
  .byte 0x03,0xC1,0x05,0x6A
| ----------------------------------------------------------
|
| SERIAL_INIT_PORT - initialize serial port for debugger communication
|
| D0 = port number (1=modem, 2=printer).
| Checks SPConfig to verify port is configured for serial,
| and checks PortAUse/PortBUse to verify port is available.
SERIAL_INIT_PORT:
        MOVE    D0,(0x3FFCD4).l                 | store port selection
        MOVE.B  (SPConfig).w,D1                 | D1 = serial port config byte
        SUBQ.W  #0x1,D0                         | port 1 (modem)?
        BNE.B   SERIAL_CHK_NIBBLE               | no - use low nibble for printer
        LSR.B   #0x4,D1                         | yes - shift high nibble (modem config)
SERIAL_CHK_NIBBLE:
        ANDI.B  #0xF,D1                         | isolate port config nibble
        BEQ.B   SERIAL_CHK_INUSE                | 0 = normal serial - OK
        SUBQ.B  #0x2,D1                         | 2 = also acceptable
        BEQ.B   SERIAL_CHK_INUSE                | OK - port available
        MOVEQ.L #-0x62,D0                       | error -98: port config mismatch
        BRA.B   SERIAL_INIT_ERR                 | return error

| ----------------------------------------------------------
|
| SERIAL_CHK_INUSE - check if serial port is currently in use
|
SERIAL_CHK_INUSE:
        LEA.L   (PortAUse).w,A0                 | A0 = port usage flags base
        MOVE.B  0x0(A0,D0.W),D1                 | D1 = usage flag for selected port
        BCLR    #0x7,D1                         | test and clear "in use" bit
        BNE.B   SERIAL_SETUP_SCC                | was set - port in use, take it anyway
        EORI.B  #0x2,D1                         | check if port is allocated
        BEQ.B   SERIAL_SETUP_SCC                | free - proceed
        MOVEQ.L #-0x61,D0                       | error -97: port in use
SERIAL_INIT_ERR:
        TST     D0                              | set flags for error return
        RTS                                     | return with error code

| ----------------------------------------------------------
|
| SERIAL_SETUP_SCC - configure SCC and establish serial link
|
| Programs the SCC with SCC_INIT_PARAMS init params, sends sync byte,
| waits for response. If no response, returns timeout error.
SERIAL_SETUP_SCC:
        BSR.B   SERIAL_SET_PORT                 | set up A0/A1 for SCC write/read
        LEA.L   SCC_INIT_PARAMS(PC),A2          | A2 = SCC init parameter table
        MOVEQ.L #0x10,D1                        | 16 bytes = 8 register/value pairs
        BSR     SCC_WRITE_REGS                  | write SCC init params
        MOVEQ.L #0x0,D0                         | send sync byte (0x00)
        BSR.B   SERIAL_SEND_BYTE                | transmit over serial
        MOVE    #-0x2000,D0                     | D0 = timeout counter (~8K loops)
SERIAL_INIT_DELAY:
        SUBQ.W  #0x1,D0                         | decrement timeout
        BNE.B   SERIAL_INIT_DELAY               | spin-wait delay
        MOVEQ.L #-0x1,D1                        | D1 = -1: enable timeout on receive
        BSR.B   SERIAL_RECV_BYTE                | try to receive response byte
        BPL     SERIAL_SET_ACTIVE               | got response - enter command loop
        MOVEQ.L #-0x8,D0                        | error -8: serial timeout
        RTS                                     | return timeout error

| ----------------------------------------------------------
|
| SERIAL_SEND_LONG - send 32-bit value over serial (MSB first)
|
SERIAL_SEND_LONG:
        MOVE.L  D0,-(SP)                        | save full long
        LSR.L   #0x8,D0                         | shift to get byte 2
        LSR.L   #0x8,D0                         | D0.W = high word of original
        BSR.B   SERIAL_SEND_WORD                | send high word (2 bytes)
        MOVE.L  (SP)+,D0                        | restore original value
| ----------------------------------------------------------
|
| SERIAL_SEND_WORD - send 16-bit value over serial (high byte first)
|
SERIAL_SEND_WORD:
        MOVE    D0,-(SP)                        | save low byte
        LSR     #0x8,D0                         | shift high byte to low position
        BSR.B   SERIAL_SEND_BYTE                | send high byte
        MOVE    (SP)+,D0                        | restore for low byte
| ----------------------------------------------------------
|
| SERIAL_SEND_BYTE - send one byte (D0.B) over SCC serial port
|
| Waits for transmit buffer empty (SCC RR0 bit 2), then
| writes byte to SCC data register (control base + 4).
| Called by: SERIAL_SEND_CMD16, SERIAL_SEND_LOOP, SERIAL_CMD_NOP, SERIAL_CMD_READ, SERIAL_READ_LOOP (and 2 more)
SERIAL_SEND_BYTE:
        BSR     SERIAL_SET_PORT                 | set A0=SCC write, A1=SCC read
        MOVE.B  (A1),D1                         | read SCC RR0 (reset read pointer)
SERIAL_TX_POLL:
        MOVE    (SP),(SP)                       | small delay (SCC recovery time)
        BTST    #0x2,(A1)                       | SCC RR0 bit 2: Tx buffer empty?
        BEQ.B   SERIAL_TX_POLL                  | not ready - keep polling
        MOVE.B  D0,0x4(A0)                      | write byte to SCC data register
        RTS                                     | return from character transmission

| ----------------------------------------------------------
|
| SERIAL_SET_PORT - set up SCC register pointers for selected port
|
| Returns A0 = SCC write control, A1 = SCC read control.
| Port 1 (modem) = channel A (+2), port 2 (printer) = channel B.
SERIAL_SET_PORT:
        MOVE.L  (SCCWr).w,A0                    | A0 = SCC write base (channel B)
        MOVE.L  (SCCRd).w,A1                    | A1 = SCC read base (channel B)
        CMPI    #0x1,(0x3FFCD4).l               | modem port selected?

        BNE.B   SERIAL_PORT_RTS                 | no - use channel B (printer)
        ADDQ.L  #0x2,A0                         | yes - advance to channel A (modem)
        ADDQ.L  #0x2,A1                         | advance A1 to channel A
SERIAL_PORT_RTS:
        RTS                                     | return with SCC registers selected

| ----------------------------------------------------------
|
| SERIAL_RECV_LONG - receive 32-bit value from serial (MSB first)
|
SERIAL_RECV_LONG:
        BSR     SERIAL_RECV_WORD                | receive high word into D0
        LSL.L   #0x8,D0                         | shift up 16 bits
        LSL.L   #0x8,D0                         | (two 8-bit shifts = 16-bit shift)
| ----------------------------------------------------------
|
| SERIAL_RECV_WORD - receive 16-bit value from serial (high byte first)
|
SERIAL_RECV_WORD:
        BSR     SERIAL_RECV_BYTE                | receive high byte
        LSL     #0x8,D0                         | shift to high position in word
| ----------------------------------------------------------
|
| SERIAL_RECV_BYTE - receive one byte from SCC serial port
|
| Polls SCC RR0 bit 0 (Rx char available). If D1 != 0,
| a timeout applies (D1 is decremented until negative).
| Returns received byte in D0.B. N flag set on timeout.
SERIAL_RECV_BYTE:
        BSR.B   SERIAL_SET_PORT                 | set A0/A1 for SCC port
SERIAL_RX_POLL:
        BTst    #0x0,(A1)                       | SCC RR0 bit 0: Rx char available?
        BNE.B   SERIAL_RX_READ                  | yes - read the byte
        TST.B   D1                              | timeout enabled (D1 nonzero)?
        BEQ.B   SERIAL_RX_POLL                  | no timeout - keep polling
        RTS                                     | timeout expired - return (N set)

| ----------------------------------------------------------
|
| SERIAL_RX_READ - read received byte from SCC data register
|
SERIAL_RX_READ:
        MOVE    (SP),(SP)                       | SCC recovery delay
        MOVE.B  0x4(A1),D0                      | read byte from SCC Rx data register
        RTS                                     | return with received byte

| ----------------------------------------------------------
|
| TRAP_WATCHER - A-line trap watcher (installed by SERIAL_CMD_WATCH)
|
| Intercepts A-line traps. If the trap number falls within
| the watched range (0x3FFCDE..0x3FFCE0), triggers a system
| error (via GenExcps+16 = line 1010 exception). Otherwise
| chains to the original A-trap dispatcher.
TRAP_WATCHER:
        MOVEM.L D0/A0,-(SP)                     | save working regs
        MOVE.L  0xA(SP),A0                      | A0 = PC at trap (from exception frame)
        MOVE    (A0),D0                         | D0 = A-line opcode at that address
        BTST    #0xB,D0                         | bit 11 set = Toolbox trap?
        BEQ.B   TRAPWATCH_OS                    | no - OS trap (8-bit number)
        ANDI    #0x1FF,D0                       | Toolbox: 9-bit trap number
        BRA.B   TRAPWATCH_CHECK                 | check against watch range

| ----------------------------------------------------------
|
| TRAPWATCH_OS - OS trap: extract 8-bit trap number
|
TRAPWATCH_OS:
        ANDI    #0xFF,D0                        | OS trap: 8-bit trap number
TRAPWATCH_CHECK:
        CMP     (0x3FFCDE).l,D0                 | below watch range low bound?
        BLT.B   TRAPWATCH_CHAIN                 | yes - pass through to original
        CMP     (0x3FFCE0).l,D0                 | above watch range high bound?
        BGT.B   TRAPWATCH_CHAIN                 | yes - pass through to original
        MOVEM.L (SP)+,D0/A0                     | restore regs
        PEA.L   GenExcps(PC)                    | push GenExcps base address
        ADDI    #0x10,(SP)                      | add 16 = line 1010 exception entry
        RTS                                     | jump to exception handler

| ----------------------------------------------------------
|
| TRAPWATCH_CHAIN - trap not in watch range: chain to original handler
|
TRAPWATCH_CHAIN:
        MOVEM.L (SP)+,D0/A0                     | restore regs
        MOVE.L  (0x3FFCDA).l,-(SP)              | push saved original A-trap vector
        RTS                                     | jump to original trap dispatcher

