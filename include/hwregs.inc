| Mac Hardware Register Addresses
| Source: MPW 1.0 HardwareEqu.a, Apple Computer Inc. 1984-1986
| Cross-referenced with minivmac CNFUDPIC.h + GLOBGLUE.c

| === VIA (6522 Versatile Interface Adapter) ===
| MPW name: VBase. Registers spaced 0x200 apart, active on odd bytes.
.equ VBase,        0xEFE1FE                     | VIA base address (= PortB)
.equ AVBufB,       0xEFE1FE                     | Port B data (RTC, mouse, sound)
.equ AVBufA,       0xEFFFFE                     | Port A data (sound, overlay, disk SEL, screen)
.equ AVBufM,       0xEFE1FE                     | Port B (mouse button bit)
.equ AVIFR,        0xEFFBFE                     | Interrupt flag register
.equ AVIER,        0xEFFDFE                     | Interrupt enable register
| Aliases using register-name convention:
.equ VIA_PortB,    AVBufB                       | Port B = VBase + 0x0000
.equ VIA_PortA,    AVBufA                       | Port A = VBase + 0x1E00
.equ VIA_DDRB,     0xEFE5FE                     | Port B data direction = VBase + 0x0400
.equ VIA_DDRA,     0xEFE7FE                     | Port A data direction = VBase + 0x0600
.equ VIA_T1CL,     0xEFE9FE                     | Timer 1 counter low = VBase + 0x0800
.equ VIA_T1CH,     0xEFEBFE                     | Timer 1 counter high = VBase + 0x0A00
.equ VIA_T1LL,     0xEFEDFE                     | Timer 1 latch low = VBase + 0x0C00
.equ VIA_T1LH,     0xEFEFFE                     | Timer 1 latch high = VBase + 0x0E00
.equ VIA_T2CL,     0xEFF1FE                     | Timer 2 counter low = VBase + 0x1000
.equ VIA_T2CH,     0xEFF3FE                     | Timer 2 counter high = VBase + 0x1200
.equ VIA_SR,       0xEFF5FE                     | Shift register (keyboard) = VBase + 0x1400
.equ VIA_ACR,      0xEFF7FE                     | Auxiliary control reg = VBase + 0x1600
.equ VIA_PCR,      0xEFF9FE                     | Peripheral control reg = VBase + 0x1800
.equ VIA_IFR,      AVIFR                        | Interrupt flag reg = VBase + 0x1A00
.equ VIA_IER,      AVIER                        | Interrupt enable reg = VBase + 0x1C00
.equ VIA_PortA2,   AVBufA                       | Port A no handshake = VBase + 0x1E00

| VIA Port A bit assignments (MPW: vSound, vSndPg2, vOverlay, vHeadSel,
| vPage2, vSCCWrReq; sysequ.inc):
| Bit 0-2: Sound volume (0-7)
| Bit 3:   Sound buffer select: 0 = alternate buffer, 1 = main buffer
|          (vSndPg2). The disk-speed (PWM) bytes are taken from the
|          selected buffer too, so the .Sony driver writes the speed value
|          into both buffers (low-memory pointers PWMBuf1, PWMBuf2)
| Bit 4:   ROM overlay (1=ROM at 0x000000, 0=RAM; cleared during boot)
|          (vOverlay; on the SE this bit is vDriveSel, the select line of
|          the two internal drives)
| Bit 5:   SEL line of the floppy drives (vHeadSel; "HD SEL" on the Mac 512
|          schematic). Together with CA0-CA2 (IWM phase lines PH0-PH2) it
|          addresses one of the 16 sense/control registers of the selected
|          drive; addressing the read-data register picks the head (side)
| Bit 6:   Screen buffer select: 0 = alternate buffer, 1 = main (vPage2)
| Bit 7:   SCC W/REQ input (vSCCWrReq): 0 = SCC channel A has a received
|          byte; the .Sony driver polls it during disk transfers

| VIA Port B bit assignments (MPW: vRTCData, vRTCClk, vRTCEnb, vSW):
| Bit 0:   RTC serial data (bidirectional)
| Bit 1:   RTC serial clock
| Bit 2:   RTC chip enable (active low)
| Bit 3:   Mouse button (1=up, 0=down)
| Bit 4:   Mouse X quadrature
| Bit 5:   Mouse Y quadrature
| Bit 6:   H-blank (1=beam in video area)
| Bit 7:   Sound disable (1=muted)

| VIA interrupt constants:
.equ VIAIntMask,   0x0100                       | SR mask for VIA (level 1) interrupts
.equ HiIntMask,    0x0300                       | SR mask IPL 3: only the programmer's switch (MPW)
.equ TicksPr100,   78                           | VIA timer cycles per 100 us (783.36 kHz: 99.6 us)

| === SCC (Zilog 8530 Serial Communications Controller) ===
| MPW names: SCCRBase (read), SCCWBase (write)
.equ SCCRBase,     0x9FFFF8                     | SCC base read address
.equ SCCWBase,     0xBFFFF9                     | SCC base write address
.equ SCC_RdCtlB,   SCCRBase                     | Channel B control read
.equ SCC_RdCtlA,   SCCRBase+2                   | Channel A control read
.equ SCC_RdDataB,  SCCRBase+4                   | Channel B data read
.equ SCC_RdDataA,  SCCRBase+6                   | Channel A data read
.equ SCC_WrCtlB,   SCCWBase                     | Channel B control write
.equ SCC_WrCtlA,   SCCWBase+2                   | Channel A control write
.equ SCC_WrDataB,  SCCWBase+4                   | Channel B data write
.equ SCC_WrDataA,  SCCWBase+6                   | Channel A data write
.equ SCCEnblMask,  0xF9FF                       | SR mask to enable SCC interrupts
| Channel A = modem port, Channel B = printer port
| Mouse tracking: DCD transitions on SCC channels = quadrature

| === IWM (Integrated Woz Machine - floppy disk controller) ===
| The IWM is selected (/DEV) anywhere in 0xC00000-0xDFFFFF. Its register
| select inputs A0-A3 are CPU address lines A9-A12 and its data bus is the
| low byte (odd addresses), so its 16 locations are 0x200 apart, from
| DBase = 0xDFE1FF (MPW HardwareEqu.a; low-memory IWM holds the base, the
| offsets ph0L..q7H are in sysequ.inc). Any access (read or write) to a
| location sets ("H", odd location) or clears ("L", even location) one of
| eight state bits, selected by A3-A1 (IWM Design Spec, "State Register"):
|   PH0-PH3    phase outputs = the drive's CA0, CA1, CA2 and LSTRB lines
|   Motor-On   drive enable: the selected /ENBLx output goes low
|   Drive-Sel  0 = /ENBL1 (internal drive), 1 = /ENBL2 (external port)
|   L6, L7     register select ("Q6", "Q7")
| L7, L6 and Motor-On select the register that the same access reads or
| writes ("x" = either):
|   L7 L6 Motor-On
|   0  0  0    read all ones
|   0  0  1    read the data register (read state)
|   0  1  x    read the status register: bit 7 = SENSE input, bit 5 = a
|              drive enable is active, bits 0-4 = mode register bits 0-4
|   1  0  x    read the write-handshake register: bit 7 = 1: write buffer
|              empty (ready for the next byte), bit 6 = 0: write underrun
|   1  1  0    write the mode register: bit 0 latch mode, bit 1 asynchronous
|              handshake, bit 2 1-second motor-off timer disabled, bit 3 fast
|              mode (2 us bit cells), bit 4 8 MHz clock, bit 5 test mode
|   1  1  1    write the data register (write load state)
| A register is read at an "L" location and written at an "H" location
| (IWM undoco features, "IWM Register Access"). The SENSE input and the
| read data input RDDATA are both wired to the drive's RD line.
.equ IWM_PH0L,    0xDFE1FF                      | PH0 = 0: drive CA0 low (MPW: DBase, DPh0L)
.equ IWM_PH0H,    0xDFE3FF                      | PH0 = 1: drive CA0 high (MPW: DPh0H)
.equ IWM_PH1L,    0xDFE5FF                      | PH1 = 0: drive CA1 low
.equ IWM_PH1H,    0xDFE7FF                      | PH1 = 1: drive CA1 high
.equ IWM_PH2L,    0xDFE9FF                      | PH2 = 0: drive CA2 low
.equ IWM_PH2H,    0xDFEBFF                      | PH2 = 1: drive CA2 high
.equ IWM_PH3L,    0xDFEDFF                      | PH3 = 0: drive LSTRB low
.equ IWM_PH3H,    0xDFEFFF                      | PH3 = 1: drive LSTRB high (strobe a control register)
.equ IWM_MTROFF,  0xDFF1FF                      | Motor-On = 0: drive enables off (MPW: DMtrOff)
.equ IWM_MTRON,   0xDFF3FF                      | Motor-On = 1: enable the selected drive (MPW: DMtrOn)
.equ IWM_INTDRV,  0xDFF5FF                      | Drive-Sel = 0: /ENBL1, internal drive
.equ IWM_EXTDRV,  0xDFF7FF                      | Drive-Sel = 1: /ENBL2, external drive
.equ IWM_Q6L,     0xDFF9FF                      | L6 = 0: read data (L7 = 0) or handshake (L7 = 1) (MPW: DiskQ6L)
.equ IWM_Q6H,     0xDFFBFF                      | L6 = 1: status (L7 = 0), mode/data write (L7 = 1) (MPW: DiskQ6H)
.equ IWM_Q7L,     0xDFFDFF                      | L7 = 0: read states (MPW: DiskQ7L)
.equ IWM_Q7H,     0xDFFFFF                      | L7 = 1: write states (MPW: DiskQ7H)

| === SCSI (NCR 5380) ===
| MPW names: scsiRd, scsiWr
.equ SCSI_Base,    0x580000                     | NCR 5380 base (MPW: scsiRd)
| NCR 5380 register offsets (from MPW HardwareEqu.a):
.equ sCDR,         0x00                         | Current SCSI Data (read) / Output Data (write)
.equ sICR,         0x10                         | Initiator Command Register
.equ sMR,          0x20                         | Mode Register
.equ sTCR,         0x30                         | Target Command Register
.equ sCSR,         0x40                         | Current SCSI Bus Status (read) / Select Enable (write)
.equ sBSR,         0x50                         | Bus & Status Register (read) / DMA Tx Start (write)
.equ sIDR,         0x60                         | Input Data (read) / Target DMA Rx Start (write)
.equ sRESET,       0x70                         | Reset Parity (read) / Initiator DMA Rx Start (write)

| === Screen and Sound constants (MPW HardwareEqu.a) ===
.equ ScreenLow,    0x3FA700                     | Screen buffer base address
.equ SoundLow,     0x3FFD00                     | Sound buffer base address (370 words; see below)
.equ romStart,     0x400000                     | ROM start address
.equ scrnBytes,    21888                        | Screen size: 512*342/8 = 21888 bytes
.equ scrnRowB,     64                           | Screen row bytes (512/8)
.equ maxX,         512                          | Screen width in pixels
.equ maxY,         342                          | Screen height in pixels
| Sound/disk-speed buffer (Inside Macintosh II-233): 370 words at SoundLow
| (main buffer; the alternate buffer is selected with VIA port A bit 3),
| one word fetched per horizontal blanking interval (44.93 us). The high
| byte drives the sound output, the low byte (odd address, MPW pwmBuffer
| = 0x3FFD01) the pulse-width modulated speed control of the 400K drives
| (PWM line of the drive connectors). The 800K drives regulate their own
| speed.

| === System Error register save area (MPW HardwareEqu.a) ===
.equ SERegs,       0x3FFC80                     | Saved registers during system error
.equ SEScrnIcon,   0x3FCB5E                     | Centered screen addr for boot icons
.equ SEScrnFace,   0x3FCCDF                     | Screen addr for sad/happy Mac face
.equ SEScrnI2,     0x3FCF1F                     | Screen addr for boot icon overlay
.equ SEScrnNum,    0x3FD3DD                     | Screen addr for error number display
.equ SEScrnInc,    0x3FD5DF                     | Screen addr for error blink animation

| === Memory Map ===
| 0x000000-0x3FFFFF  RAM (4MB max, mirrored in smaller configs)
| 0x400000-0x41FFFF  ROM (128KB, aliased at 0x000000 during overlay)
| 0x580000-0x5FFFFF  SCSI (NCR 5380)
| 0x600000-0x7FFFFF  RAM with overlay on (MPW: ovlyRAM = $600000)
| 0x800000-0x9FFFFF  SCC read
| 0xA00000-0xBFFFFF  SCC write
| 0xC00000-0xDFFFFF  IWM disk controller (locations DBase + n*0x200, DBase = 0xDFE1FF)
| 0xE80000-0xEFFFFF  VIA
