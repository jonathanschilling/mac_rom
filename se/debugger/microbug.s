| MicroBug -- the built-in ROM debugger
|
| Entered from SysErr2 (os/sys_error.s) when no external debugger
| (MacsBug) is installed and the programmer's switch is pressed.
| Provides a hex expression parser and a small command set:
|
| G   - resume (go)
| DM  - display memory
| SM  - set memory
| TD  - total display (all saved registers)
| PC  - display/set PC
| SR  - display/set SR
| Dn/An - display/set a data or address register
|
| Saved CPU state lives in SERegs at 0x3FFC80; the command buffer and
| MicroBug state live at 0x3FFCD4..0x3FFCFC. The 128K/512K ROM has no ROM
| debugger; the Mac Plus has the same MicroBug.
|
| MicroBug variables:
| 0x3FFCF6 expression negate flag
| 0x3FFCF8 dot address ("." in expressions)
| 0x3FFCFC DM continuation address
| 0x3FFCD4 serial port selection (1=modem, 2=printer)
| 0x3FFCDA saved A-line trap vector
| 0x3FFCDE trap watch range low
| 0x3FFCE0 trap watch range high
|
| References:
| Technical Note TN1136: MicroBug, The ROM Debugger

| ----------------------------------------------------------
| MICROBUG_ENTRY - MicroBug entry: built-in ROM debugger
| Entered when DS error 13 (dsNoPk) occurs or no external
| debugger is installed. Sets up a simple command-line interface
| with hex expression evaluation and memory display/set commands.
| MicroBug variables at $3FFCD4-$3FFCFC (see TN1136).
MICROBUG_ENTRY:
    ADDQ.L      #0x2,A7                         | pop error code from stack
    LEA.L       (DSAlertRect).W,A0              | A0 = DS alert rect
    BSR.W       SET_DEFAULT_RECT                | draw default alert frame
    MOVE.L      #0x460026,-(A7)                 | push port origin (70, 38)
    _MovePortTo                                 | position MicroBug display area
    BSR.W       COPY_ALERT_RECT                 | offset alert rect to port
    SUBA.W      #0x10,A7                        | allocate 16-byte event record
    CLR.W       D7                              | D7 = 0 (MicroBug state flags)
    CLR.L       (0x3FFCF8).L                    | clear dot address ("." variable)
    CLR.L       (0x3FFCFC).L                    | clear DM continuation address
| ----------------------------------------------------------
|
| MICROBUG_PROMPT - MicroBug prompt: clear input line, draw ">" prompt
|
| ----------------------------------------------------------
| MICROBUG_PROMPT - clear input area, show ">" prompt
| Uses SERegs area ($3FFCD4-$3FFCF6) as the 34-byte input buffer.
MICROBUG_PROMPT:
    MOVE.L      #0x1101B0,-(A7)                 | push erase rect (17, 432)
    CLR.L       -(A7)                           | push erase rect origin (0, 0)
    BSR.W       ERASE_STACK_RECT                | erase input line area
    LEA.L       (0x3FFCF6).L,A6                 | A6 = end of input buffer
    MOVEQ.L     #0x0,D6                         | D6 = 0 (char counter)
| Fill input buffer with spaces (34 bytes, top-down)
MICROBUG_FILL_BUF:
    MOVE.W      #0x20,-(A6)                     | fill with space characters
    ADDQ.W      #0x2,D6                         | count 2 bytes
    CMPI.W      #0x22,D6                        | filled 34 bytes?
    BNE.B       MICROBUG_FILL_BUF               | no: continue filling
    MOVEA.L     A6,A4                           | A4 = buffer start (write position)
    MOVE.L      #0xF000A,-(A7)                  | push position (15, 10)
    _MoveTo                                     | move pen to prompt position
    MOVEQ.L     #0x3E,D0                        | D0 = '>' character
    MOVE.W      D0,-(A7)                        | push character
    _DrawChar                                   | draw ">" prompt
| ----------------------------------------------------------
|
| MICROBUG_KEY_LOOP - keyboard input loop: read characters into buffer
|
| Polls for keyboard events, converts lowercase to uppercase,
| handles Return (execute), Backspace (delete), and printable chars.
| Input buffer: A4=start, A6=current write position.
| D6 = remaining character slots.
| Called by: MICROBUG_CHECK_KEY, MICROBUG_STORE_CH, MICROBUG_KEY_LOOP
| MicroBug keyboard input loop: poll for key events
MICROBUG_KEY_LOOP:
    MOVEA.L     A7,A0                           | A0 = event record on stack
    MOVEQ.L     #0x8,D0                         | D0 = keyDown event mask
    _GetOSEvent                                 | poll for keyboard event
    BNE.B       MICROBUG_KEY_LOOP               | no event: keep polling
    MOVE.L      0x2(A7),D0                      | D0 = event message (char in low byte)
    BCLR        #0x7,D0                         | clear high bit (meta key flag)
    CMPI.B      #0x61,D0                        | lowercase 'a' or above?
    BLT.B       MICROBUG_CHECK_KEY              | no: check for special keys
    BCLR        #0x5,D0                         | yes: convert to uppercase
MICROBUG_CHECK_KEY:
    CMPI.B      #0xD,D0                         | Return key?
    BEQ.B       MICROBUG_EXEC_CMD               | yes: execute command
    CMPI.B      #0x8,D0                         | Backspace key?
    BNE.B       MICROBUG_STORE_CH               | no: store character
    CMPA.L      A6,A4                           | buffer empty (A4 == A6)?
    BEQ.B       MICROBUG_KEY_LOOP               | yes: ignore backspace
    ADDQ.W      #0x1,D6                         | one more slot available
    SUBQ.L      #0x1,A6                         | back up write position
| Backspace: erase last character from screen
    SUBQ.L      #0x4,A7                         | room for pen position
    MOVE.L      A7,-(A7)                        | push ptr for GetPen
    _GetPen                                     | get current pen position
    MOVE.L      (A7),-(A7)                      | duplicate pen position
    SUBQ.L      #0x2,A7                         | room for CharWidth result
    MOVE.B      (A6),D0                         | D0 = character being deleted
    MOVE.W      D0,-(A7)                        | push character
    _CharWidth                                  | get width of deleted character
    MOVE.W      (A7)+,D3                        | D3 = char width in pixels
    SUB.W       D3,0x2(A7)                      | move pen left by char width
    CLR.W       (A7)                            | clear top of rect
    MOVE.L      A7,-(A7)                        | push erase rect ptr
    CLR.W       -(A7)                           | push offset dV = 0
    MOVE.W      #0x2,-(A7)                      | push offset dH = 2
    _OffsetRect                                 | expand rect slightly right
    BSR.W       ERASE_STACK_RECT                | erase the character area
    MOVE.W      D3,-(A7)                        | push char width
    NEG.W       (A7)                            | negate (move left)
    CLR.W       -(A7)                           | dV = 0
    _Move                                       | move pen left by char width
    BRA.B       MICROBUG_KEY_LOOP               | continue key loop
| ----------------------------------------------------------
|
| MICROBUG_STORE_CH - store printable character in buffer and echo it
|
MICROBUG_STORE_CH:
    TST.W       D6                              | buffer full?
    BEQ.B       MICROBUG_KEY_LOOP               | yes: ignore character
    SUBQ.W      #0x1,D6                         | one fewer slot available
    MOVE.B      D0,(A6)+                        | store character in buffer
    MOVE.W      D0,-(A7)                        | push character
    _DrawChar                                   | echo character to screen
    BRA.B       MICROBUG_KEY_LOOP               | continue key loop
| ----------------------------------------------------------
|
| MICROBUG_EXEC_CMD - Return pressed: parse and dispatch command
|
| If input is empty, re-submit the previous command (D7).
| Otherwise read the first two chars as command code and
| look up in DT_DbgCmdTab for dispatch.
| Return pressed: parse and execute MicroBug command
MICROBUG_EXEC_CMD:
    CMPA.L      A4,A6                           | empty input (no chars typed)?
    BNE.B       MICROBUG_PARSE_CMD              | no: parse new command
    MOVE.W      D7,(A6)+                        | yes: re-submit last command
MICROBUG_PARSE_CMD:
    MOVE.W      (A4)+,D7                        | D7 = 2-char command code
    LEA.L       DT_DbgCmdTab(PC),A0             | A0 = command table base
MICROBUG_CMD_LOOP:
    MOVE.W      (A0)+,D0                        | D0 = table entry command code
    BMI.B       MICROBUG_CMD_DONE               | $FFFF = end of table
    MOVE.W      (A0)+,D2                        | D2 = handler offset from table
    CMPI.B      #0x40,D0                        | is it '@' (register command)?
    BNE.B       MICROBUG_CMD_CMP                | no: direct compare
    MOVE.B      D7,D0                           | yes: D0 = register digit
    CMPI.B      #0x30,D0                        | digit >= '0'?
    BMI.B       MICROBUG_CMD_LOOP               | no: skip this entry
    CMPI.B      #0x37,D0                        | digit <= '7'?
    BGT.B       MICROBUG_CMD_LOOP               | no: skip this entry
MICROBUG_CMD_CMP:
    CMP.W       D0,D7                           | command code matches input?
    BNE.B       MICROBUG_CMD_LOOP               | no: try next entry
    LEA.L       DT_DbgCmdTab(PC),A0             | A0 = table base (for offset)
    JSR         0x0(A0,D2.W)                    | call command handler
MICROBUG_CMD_DONE:
    BRA.W       MICROBUG_PROMPT                 | redraw prompt for next command
| ----------------------------------------------------------
|
| DT_DbgCmdTab - MicroBug command dispatch table
|
| Each entry: 2-byte command code, 2-byte offset from table base.
| '@' (0x40) in low byte = register command (D0-D7 or A0-A7).
| "G " = Go, "DM" = Dump Memory, "SM" = Set Memory,
| "TD" = Total Display, "D@" = Data reg, "A@" = Addr reg,
| "PC" = Program Counter, "SR" = Status Register.
| DT_DbgCmdTab - MicroBug command dispatch table
| Format: 2-byte command code, 2-byte handler offset from table base.
| '@' in low byte = register command (D0-D7 or A0-A7, digit 0-7).
DT_DbgCmdTab:
    .short 0x4720, 0x0022                       | "G " = Go (resume execution)
    .short 0x444D, 0x0046                       | "DM" = Dump Memory
    .short 0x534D, 0x00C6                       | "SM" = Set Memory
    .short 0x5444, 0x00F2                       | "TD" = Total Display (all regs)
    .short 0x4440, 0x0100                       | "D@" = Data register (D0-D7)
    .short 0x4140, 0x0108                       | "A@" = Address register (A0-A7)
    .short 0x5043, 0x0110                       | "PC" = Program Counter
    .short 0x5352, 0x0118                       | "SR" = Status Register
    .short 0xFFFF                               | end of table sentinel
| ----------------------------------------------------------
| P_DbgCmd_G - "G " (Go): resume execution at address
| If expression given, jumps to that address. If empty,
| resumes from the saved exception PC.
P_DbgCmd_G:
    BSR.W       EVAL_EXPR                       | parse address expression
    BEQ.B       DBGCMD_G_RESUME                 | empty: resume from saved PC
    MOVE.L      D0,-(A7)                        | push target address (for RTS)
    BSR.W       INSTALL_INF_RGN                 | restore infinite region
    RTS                                         | "return" to target address
DBGCMD_G_RESUME:
    ADDA.W      #0x14,A7                        | clean up MicroBug stack frame
    CLR.B       (DSWndUpdate).W                 | no DS window update needed
    BRA.W       DSERR_RESUME                    | resume from error via RTE
| ----------------------------------------------------------
|
| ERASE_STACK_RECT - erase rectangle area on stack
|
| The caller pushes a rect (8 bytes) before calling. ERASE_STACK_RECT pops
| the return address, calls EraseRect on the stacked rect,
| then cleans up and jumps back to the caller.
| ----------------------------------------------------------
| ERASE_STACK_RECT - erase rectangle pushed on stack by caller
| Caller pushes 8-byte rect before BSR. This routine pops the
| return address, erases the rect, pops it, and returns.
ERASE_STACK_RECT:
    MOVEA.L     (A7)+,A2                        | A2 = return address
    MOVE.L      A7,-(A7)                        | push rect ptr (on stack)
    _EraseRect                                  | erase the rectangle
    ADDQ.L      #0x8,A7                         | pop the 8-byte rect
    JMP         (A2)                            | tail-call return from ERASE_STACK_RECT via A2
| ----------------------------------------------------------
| P_DbgCmd_DM - "DM" (Dump Memory): display hex memory dump
| Shows 6 rows of 8 words each, starting at parsed address
| or continuation from last DM command.
P_DbgCmd_DM:
    MOVE.L      #0x7001B0,-(A7)                 | push erase rect (112, 432)
    CLR.L       -(A7)                           | push erase rect origin (0, 0)
    BSR.B       ERASE_STACK_RECT                | erase dump area
    BSR.W       PARSE_ADDR_OR_CONT              | D0 = address (or continuation)
    BCLR        #0x0,D0                         | word-align address
    MOVEA.L     D0,A3                           | A3 = dump start address
    MOVE.L      D0,(0x3FFCF8).L                 | save as dot address (".")
    MOVEQ.L     #0x5,D6                         | D6 = 6 rows
    MOVEQ.L     #0xF,D5                         | D5 = initial Y position
DM_ROW_LOOP:
    ADDI.W      #0xF,D5                         | advance Y by 15 pixels
    MOVE.W      #0xA,-(A7)                      | push X = 10
    MOVE.W      D5,-(A7)                        | push Y position
    _MoveTo                                     | position for address column
    MOVE.L      A3,D0                           | D0 = current address
    BSR.B       PRINT_HEX_LONG                  | print 8-digit address
    MOVEQ.L     #0x7,D4                         | D4 = 8 words per row
    MOVEQ.L     #0x23,D3                        | D3 = initial X for data
DM_WORD_LOOP:
    ADDI.W      #0x2D,D3                        | advance X by 45 pixels
    MOVE.W      D3,-(A7)                        | push X position
    MOVE.W      D5,-(A7)                        | push Y position
    _MoveTo                                     | position for next word
    MOVE.W      (A3)+,D0                        | D0 = next word from memory
    BSR.B       PRINT_HEX_WORD                  | print 4-digit hex word
    DBF.W       D4,DM_WORD_LOOP                 | loop for 8 words
    DBF.W       D6,DM_ROW_LOOP                  | loop for 6 rows
    MOVE.L      A3,(0x3FFCFC).L                 | save continuation address
    RTS                                         | return from P_DbgCmd_DM
| ----------------------------------------------------------
|
| PRINT_HEX_LONG - print 32-bit hex value (8 digits)
|
| Prints D0 as 8 hex digits by printing high word then low word.
PRINT_HEX_LONG:
    SWAP.W      D0                              | swap to print high word first
    BSR.B       PRINT_HEX_BYTE                  | print high word as hex
    SWAP.W      D0                              | swap back for low word
| ----------------------------------------------------------
|
| PRINT_HEX_WORD - print 16-bit hex value (4 digits)
|
PRINT_HEX_WORD:
    MOVE.W      D0,-(A7)                        | save low byte
    ROXR.W      #0x8,D0                         | shift high byte to low position
    BSR.B       PRINT_HEX_BYTE                  | print high byte
    MOVE.W      (A7)+,D0                        | restore low byte
| ----------------------------------------------------------
|
| PRINT_HEX_BYTE - print 8-bit hex value (2 digits)
|
PRINT_HEX_BYTE:
    MOVE.W      D0,-(A7)                        | save byte value
    ROR.W       #0x4,D0                         | shift high nibble to low position
    BSR.B       PRINT_HEX_NIBBLE                | print high nibble
    MOVE.W      (A7)+,D0                        | restore byte for low nibble
| ----------------------------------------------------------
|
| PRINT_HEX_NIBBLE - print single hex nibble (low 4 bits of D0)
|
PRINT_HEX_NIBBLE:
    ANDI.B      #0xF,D0                         | isolate low nibble
    ORI.B       #0x30,D0                        | convert to ASCII '0'-'9'
    CMPI.B      #0x39,D0                        | > '9'?
    BLE.B       HEX_DIGIT_OK                    | no - digit is correct
    ADDQ.W      #0x7,D0                         | yes - adjust to 'A'-'F'
HEX_DIGIT_OK:
    MOVE.L      D0,-(A7)                        | save D0 (for return value)
    MOVE.W      D0,-(A7)                        | push character to draw
    _DrawChar                                   | draw hex digit character
    MOVE.L      (A7)+,D0                        | restore D0
    RTS                                         | return from PRINT_HEX_NIBBLE
| ----------------------------------------------------------
| P_DbgCmd_FS (SM) - "SM" (Set Memory): write values to memory
| Parses address, then reads hex values separated by spaces
| and stores them byte-by-byte at the target address.
| After all values are written, does a DM to verify.
P_DbgCmd_FS:
    BSR.W       PARSE_ADDR_OR_CONT              | D0 = target address
    MOVEA.L     D0,A1                           | A1 = write address
    LEA.L       (0x3FFCF8).L,A0                 | A0 = dot + continuation vars
    MOVE.L      D0,(A0)+                        | set dot address
    MOVE.L      D0,(A0)+                        | set continuation address
    MOVE.W      #0x444D,D7                      | D7 = "DM" (next auto-command)
SM_PARSE_LOOP:
    BSR.W       EVAL_EXPR                       | parse next hex value
    BEQ.W       P_DbgCmd_DM                     | end of input: show dump
    MOVEA.L     A1,A2                           | A2 = current write position
SM_STORE_LOOP:
    MOVE.B      D0,-0x1(A2,D1.W)                | store byte (big-endian order)
    ASR.L       #0x8,D0                         | shift to next byte
    ADDQ.L      #0x1,A1                         | advance write position
    SUBQ.L      #0x1,D1                         | decrement byte count
    BNE.B       SM_STORE_LOOP                   | more bytes: continue
    BRA.B       SM_PARSE_LOOP                   | parse next value
| ----------------------------------------------------------
| P_DbgCmd_TD - "TD" (Total Display): dump all saved registers
| Sets continuation to SERegs ($3FFC80) and falls into DM.
P_DbgCmd_TD:
    MOVE.L      #0x3FFC80,(0x3FFCFC).L          | continuation = SERegs base
    BRA.W       P_DbgCmd_DM                     | display as memory dump
| P_DbgCmd_Dn - "D0"-"D7": display/set data register
    LEA.L       (0x3FFC80).L,A3                 | A3 = SERegs D0-D7 base
    BRA.B       DBGREG_PARSE_NUM                | parse register number
| P_DbgCmd_An - "A0"-"A7": display/set address register
    LEA.L       (0x3FFCA0).L,A3                 | A3 = SERegs A0-A7 base
    BRA.B       DBGREG_PARSE_NUM                | parse register number
| ----------------------------------------------------------
| P_DbgCmd_PC - "PC" (Program Counter): display or set saved PC
P_DbgCmd_PC:
    LEA.L       (0x3FFCC0).L,A3                 | A3 = MacsBugPC in SERegs
    BRA.B       DBGREG_PARSE_VAL                | parse value or display
| ----------------------------------------------------------
| P_DbgCmd_SR - "SR" (Status Register): display or set saved SR
P_DbgCmd_SR:
    LEA.L       (0x3FFCC4).L,A3                 | A3 = MacsBugSR in SERegs
    BSR.B       EVAL_EXPR                       | parse new SR value
    BEQ.B       DBGREG_SHOW_WORD                | no value: display current SR
    MOVE.W      D0,(A3)                         | set new SR value
    RTS                                         | return from P_DbgCmd_SR
| ----------------------------------------------------------
|
| DBGREG_PARSE_NUM - parse register number and optional value for Dx/Ax
|
DBGREG_PARSE_NUM:
    BSR.B       ASCII_TO_NIBBLE                 | convert register digit to 0-7
    LSL.L       #0x2,D0                         | D0 = reg# * 4 (longword offset)
    ADDA.L      D0,A3                           | A3 = address of register in SERegs
DBGREG_PARSE_VAL:
    BSR.B       EVAL_EXPR                       | parse new value expression
    BEQ.B       DBGREG_DISPLAY                  | no value: display current
    MOVE.L      D0,(A3)                         | set register to new value
    RTS                                         | return from DBGREG_PARSE_VAL
| ----------------------------------------------------------
|
| DBGREG_SHOW_WORD - SR display: flag for word-sized display
|
DBGREG_SHOW_WORD:
    MOVEQ.L     #-0x1,D6                        | D6 = -1 (flag: word-sized display)
| ----------------------------------------------------------
|
| DBGREG_DISPLAY - display register value from save area
|
| Display register value (longword for D/A/PC, word for SR)
DBGREG_DISPLAY:
    MOVE.L      #0x7001B0,-(A7)                 | push erase rect (112, 432)
    CLR.L       -(A7)                           | push erase rect origin (0, 0)
    BSR.W       ERASE_STACK_RECT                | erase display area
    MOVE.L      #0x300010,-(A7)                 | push position (48, 16)
    _MoveTo                                     | position for value display
    MOVE.W      (A3)+,D0                        | D0 = high word of register
    TST.W       D6                              | word-sized (SR)?
    BNE.B       DBGREG_PRINT_LOW                | yes: skip high word
    BSR.W       PRINT_HEX_WORD                  | print high word
    MOVE.W      (A3)+,D0                        | D0 = low word
DBGREG_PRINT_LOW:
    BSR.W       PRINT_HEX_WORD                  | print low word
    RTS                                         | return from DBGREG_DISPLAY
| ----------------------------------------------------------
|
| ASCII_TO_NIBBLE - convert ASCII hex character in D0 to 0-15
|
| Same algorithm as TN1136's StringToNumber: if > '9',
| subtract 7 to map 'A'-'F' to 10-15, then mask low nibble.
ASCII_TO_NIBBLE:
    ANDI.L      #0xFF,D0                        | isolate ASCII byte
    CMPI.B      #0x39,D0                        | > '9'?
    BLE.B       NIBBLE_IS_DIGIT                 | no - '0'-'9' range
    SUBQ.B      #0x7,D0                         | adjust 'A'-'F' to 0x3A-0x3F
NIBBLE_IS_DIGIT:
    ANDI.B      #0xF,D0                         | mask to nibble value (0-15)
    RTS                                         | return from ASCII_TO_NIBBLE
| ----------------------------------------------------------
|
| PARSE_ADDR_OR_CONT - parse address, defaulting to DM continuation address
|
| If the user typed an expression, returns it in D0.
| Otherwise returns the DM continuation address (for "DM" alone).
PARSE_ADDR_OR_CONT:
    BSR.B       EVAL_EXPR                       | try to parse expression
    BNE.B       PARSE_ADDR_RTS                  | got one - return it in D0
    MOVE.L      (0x3FFCFC).L,D0                 | no arg - use continuation address
PARSE_ADDR_RTS:
    RTS                                         | return from PARSE_ADDR_RTS
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
| Called by: P_DbgCmd_G, SM_PARSE_LOOP, P_DbgCmd_SR, DBGREG_PARSE_VAL, PARSE_ADDR_OR_CONT
EVAL_EXPR:
    MOVEQ.L     #0x0,D4                         | D4 = 0: accumulated result
    MOVEQ.L     #0x0,D6                         | D6 = 0: max expression size
| ----------------------------------------------------------
|
| EXPR_NEW_TERM - start parsing a new term in the expression
|
EXPR_NEW_TERM:
    MOVEQ.L     #0x0,D5                         | D5 = 0 (digit count for this term)
    CLR.W       (0x3FFCF6).L                    | clear negate flag
    MOVEQ.L     #0x0,D3                         | D3 = 0 (indirection count)
    MOVEQ.L     #0x0,D0                         | D0 = 0 (current character)
    MOVEQ.L     #0x0,D1                         | D1 = 0 (current term value)
| ----------------------------------------------------------
|
| EXPR_SKIP_SPACE - skip whitespace and control chars in input
|
EXPR_SKIP_SPACE:
    CMPA.L      A6,A4                           | end of input buffer?
    BGE.W       EXPR_FINALIZE                   | yes: finalize what we have
EXPR_SCAN_PREFIX:
    MOVE.B      (A4)+,D0                        | read next character
    CMPI.B      #0x20,D0                        | space or control char?
    BLE.B       EXPR_SKIP_SPACE                 | yes: skip whitespace
    CMPI.B      #0x40,D0                        | '@' (indirection)?
    BNE.B       EXPR_CHECK_OP                   | no: check for operator
    ADDQ.W      #0x1,D3                         | yes: increment deref count
    BRA.B       EXPR_SCAN_PREFIX                | scan next prefix char
| ----------------------------------------------------------
|
| EXPR_CHECK_OP - check for +/- operators between terms
|
EXPR_CHECK_OP:
    CMPI.B      #0x2B,D0                        | '+' (add)?
    BEQ.B       EXPR_SCAN_PREFIX                | yes: skip, continue scanning
    CMPI.B      #0x2D,D0                        | '-' (subtract)?
    BNE.B       EXPR_CHECK_HEX                  | no: check for hex/token
    NOT.B       (0x3FFCF6).L                    | toggle negate flag
    BRA.B       EXPR_SCAN_PREFIX                | continue scanning prefix
| ----------------------------------------------------------
|
| EXPR_CHECK_HEX - check for '$' hex prefix or bare hex number
|
EXPR_CHECK_HEX:
    CMPI.B      #0x24,D0                        | '$' (explicit hex prefix)?
    BNE.W       EXPR_CHECK_DOT                  | no: check for '.' or token
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.B      (A4)+,D0                        | read first hex digit
| ----------------------------------------------------------
|
| EXPR_HEX_LOOP - hex digit accumulation loop
|
| Converts each ASCII char to 0-15 via ASCII_TO_NIBBLE (forgiving: any
| char that isn't a digit just contributes its low nibble,
| which is why "G FINDER" evaluates to an odd address).
| Called by: EXPR_READ_REGNUM, EXPR_HEX_LOOP, EXPR_CHECK_REG, EXPR_CHECK_RD
EXPR_HEX_LOOP:
    BSR.B       ASCII_TO_NIBBLE                 | convert char to nibble (0-15)
    ADDQ.W      #0x1,D5                         | count digit
    LSL.L       #0x4,D1                         | shift value left 4 bits
    ADD.L       D0,D1                           | add new nibble
    CMPA.L      A6,A4                           | end of input?
    BGE.B       EXPR_FINALIZE                   | yes: finalize
    MOVE.B      (A4)+,D0                        | read next char
    CMPI.B      #0x30,D0                        | is it >= '0' (hex digit)?
    BGE.B       EXPR_HEX_LOOP                   | yes: accumulate more digits
| ----------------------------------------------------------
|
| EXPR_FINALIZE - finalize current term: apply indirection and negate
|
| Finalize current term: apply '@' indirection and '-' negate
EXPR_FINALIZE:
    TST.W       D3                              | any '@' indirections?
    BEQ.B       EXPR_CHECK_NEG                  | no: check negate
    MOVEQ.L     #0x8,D5                         | D5 = 8 (long-sized result)
EXPR_DEREF_LOOP:
    BCLR        #0x0,D1                         | word-align address
    MOVEA.L     D1,A0                           | A0 = pointer to dereference
    MOVE.L      (A0),D1                         | D1 = dereferenced value
    SUBQ.W      #0x1,D3                         | decrement deref count
    BNE.B       EXPR_DEREF_LOOP                 | more '@': keep dereferencing
EXPR_CHECK_NEG:
    TST.B       (0x3FFCF6).L                    | negate flag set?
    BEQ.B       EXPR_ACCUMULATE                 | no: add term as-is
    NEG.L       D1                              | yes: negate term value
EXPR_ACCUMULATE:
    ADD.L       D1,D4                           | accumulate into result
| Compute expression size from digit count
    ADDQ.W      #0x1,D5                         | round up
    LSR.W       #0x1,D5                         | D5 = (digits+1)/2 = byte count
    CMPI.W      #0x4,D5                         | cap at 4 (longword)
    BLE.B       EXPR_CHECK_SIZE                 | within range: keep
    MOVEQ.L     #0x4,D5                         | cap at 4 bytes
EXPR_CHECK_SIZE:
    CMP.W       D6,D5                           | bigger than max so far?
    BLE.B       EXPR_CHECK_NEXT                 | no: keep current max
    MOVE.W      D5,D6                           | yes: update max size
EXPR_CHECK_NEXT:
    CMPI.B      #0x2B,D0                        | '+' follows?
    BEQ.B       EXPR_NEXT_TERM                  | yes: parse next term
    CMPI.B      #0x2D,D0                        | '-' follows?
    BNE.B       EXPR_RETURN                     | no: expression complete
EXPR_NEXT_TERM:
    MOVE.B      D0,-(A4)                        | push back operator for next term
    BRA.W       EXPR_NEW_TERM                   | parse next term
| ----------------------------------------------------------
|
| EXPR_RETURN - expression complete: return value and size
|
EXPR_RETURN:
    MOVE.L      D4,D0                           | D0 = expression value
    MOVE.L      D6,D1                           | D1 = expression size (bytes)
    RTS                                         | return (Z=1 if D0==0)
| ----------------------------------------------------------
|
| EXPR_CHECK_DOT - check for '.' (dot address) or register tokens
|
EXPR_CHECK_DOT:
    CMPI.B      #0x2E,D0                        | '.' (dot = last address)?
    BNE.B       EXPR_CHECK_PC                   | no: check PC/register
    MOVE.L      (0x3FFCF8).L,D1                 | D1 = dot address value
    MOVEQ.L     #0x1,D2                         | D2 = 1 char to consume
| ----------------------------------------------------------
|
| EXPR_TOKEN_DONE - common path for '.', PC, and register tokens
|
| D1 = value, D2 = chars to consume from input buffer.
EXPR_TOKEN_DONE:
    MOVEQ.L     #0x8,D5                         | D5 = 8 (long-sized token)
EXPR_SKIP_CHARS:
    MOVE.B      (A4)+,D0                        | consume token characters
    SUBQ.W      #0x1,D2                         | more chars to skip?
    BNE.B       EXPR_SKIP_CHARS                 | yes: skip next
    BRA.B       EXPR_FINALIZE                   | done: finalize term
| ----------------------------------------------------------
|
| EXPR_CHECK_PC - check for "PC" (program counter) token
|
EXPR_CHECK_PC:
    MOVE.W      D0,D2                           | D2 = first char in high byte
    LSL.W       #0x8,D2                         | shift to make room for second
    MOVE.B      (A4),D2                         | D2 = 2-char token
    CMPI.W      #0x5043,D2                      | "PC" token?
    BNE.B       EXPR_CHECK_REG                  | no: check for register
    MOVE.L      (0x3FFCC0).L,D1                 | D1 = saved PC (MacsBugPC)
    MOVEQ.L     #0x2,D2                         | D2 = 2 chars to consume
    BRA.B       EXPR_TOKEN_DONE                 | finalize PC token
| ----------------------------------------------------------
|
| EXPR_CHECK_REG - check for "RAx" or "RDx" register tokens
|
EXPR_CHECK_REG:
    CMPI.B      #0x52,D0                        | first char = 'R' (register)?
    BNE.W       EXPR_HEX_LOOP                   | no: treat as hex digit
    CMPI.B      #0x41,D2                        | second char = 'A' (address reg)?
    BNE.B       EXPR_CHECK_RD                   | no: check data register
    LEA.L       (0x3FFCA0).L,A0                 | A0 = SERegs A0-A7 base
| ----------------------------------------------------------
|
| EXPR_READ_REGNUM - read register number and fetch saved value
|
EXPR_READ_REGNUM:
    MOVEQ.L     #0x0,D2                         | clear D2
    MOVE.B      0x1(A4),D2                      | D2 = register digit char
    SUBI.W      #0x30,D2                        | convert '0'-'7' to 0-7
    BMI.W       EXPR_HEX_LOOP                   | < 0: not a digit, treat as hex
    CMPI.W      #0x7,D2                         | > 7?
    BGT.W       EXPR_HEX_LOOP                   | yes: not valid register
    LSL.W       #0x2,D2                         | D2 = reg# * 4 (longword offset)
    MOVE.L      0x0(A0,D2.W),D1                 | D1 = saved register value
    MOVEQ.L     #0x3,D2                         | D2 = 3 chars to consume (RAn)
    BRA.B       EXPR_TOKEN_DONE                 | finalize register token
| ----------------------------------------------------------
|
| EXPR_CHECK_RD - check for "RDx" (data register) token
|
EXPR_CHECK_RD:
    CMPI.B      #0x44,D2                        | second char = 'D' (data reg)?
    BNE.W       EXPR_HEX_LOOP                   | no: treat 'R' as hex
    LEA.L       (0x3FFC80).L,A0                 | A0 = SERegs D0-D7 base
    BRA.B       EXPR_READ_REGNUM                | read register number digit
