| Mac Hardware Register Addresses
| Source: MPW 1.0 HardwareEqu.a, Apple Computer Inc. 1984-1986
| Cross-referenced with minivmac CNFUDPIC.h + GLOBGLUE.c

| === VIA (6522 Versatile Interface Adapter) ===
| MPW name: VBase. Registers spaced 0x200 apart, active on odd bytes.
.equ VBase,        0xEFE1FE                     | VIA base address (= PortB)
.equ AVBufB,       0xEFE1FE                     | Port B data (RTC, mouse, sound)
.equ AVBufA,       0xEFFFFE                     | Port A data (sound vol, overlay, IWM)
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

| VIA Port A bit assignments (MPW: vSndVol, vOverlay, vHeadSel, vPage2):
| Bit 0-2: Sound volume (0-7)
| Bit 3:   Sound buffer page select (0=main, 1=alternate)
| Bit 4:   ROM overlay (1=ROM at 0x000000, 0=RAM; cleared during boot)
| Bit 5:   IWM SEL line (disk drive head select)
| Bit 6:   Screen buffer page select
| Bit 7:   SCC wait/request

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
.equ HiIntMask,    0x0300                       | SR mask for all maskable interrupts
.equ TicksPr100,   78                           | Timer 1 setting for 100 usec intervals

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

| === IWM (Integrated Woz Machine - disk controller) ===
| Base: 0xC00000, registers spaced 0x200 apart
| MPW names: DMtrOff, DMtrOn
.equ IWM_PH0L,    0xDFE1FF                      | Phase 0 off
.equ IWM_PH0H,    0xDFE3FF                      | Phase 0 on
.equ IWM_PH1L,    0xDFE5FF                      | Phase 1 off
.equ IWM_PH1H,    0xDFE7FF                      | Phase 1 on
.equ IWM_PH2L,    0xDFE9FF                      | Phase 2 off
.equ IWM_PH2H,    0xDFEBFF                      | Phase 2 on
.equ IWM_PH3L,    0xDFEDFF                      | Phase 3 off
.equ IWM_PH3H,    0xDFEFFF                      | Phase 3 on
.equ IWM_MTROFF,  0xDFF1FF                      | Motor off (MPW: DMtrOff)
.equ IWM_MTRON,   0xDFF3FF                      | Motor on (MPW: DMtrOn)
.equ IWM_INTDRV,  0xDFF5FF                      | Select internal drive
.equ IWM_EXTDRV,  0xDFF7FF                      | Select external drive
.equ IWM_Q6L,     0xDFF9FF                      | Q6 low (shift/read)
.equ IWM_Q6H,     0xDFFBFF                      | Q6 high (load/write)
.equ IWM_Q7L,     0xDFFDFF                      | Q7 low (read mode)
.equ IWM_Q7H,     0xDFFFFF                      | Q7 high (write mode)

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
.equ SoundLow,     0x3FFD00                     | Sound buffer base address
.equ romStart,     0x400000                     | ROM start address
.equ scrnBytes,    21888                        | Screen size: 512*342/8 = 21888 bytes
.equ scrnRowB,     64                           | Screen row bytes (512/8)
.equ maxX,         512                          | Screen width in pixels
.equ maxY,         342                          | Screen height in pixels

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
| 0xC00000-0xDFFFFF  IWM disk controller
| 0xE80000-0xEFFFFF  VIA
