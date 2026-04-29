| QuickDraw macros converted from GrafTypes.a
| Original: 102658076_quickdraw_acc/QuickDraw Source/GrafTypes.a

| --------------------------------------------------------------
|  UNLINK A6, STRIP PARAMETERS, AND RETURN.
|  FIRST PARAM IS NUMBER OF BYTES OF STACK BIAS.
|
.macro UNLINK paramsize
  unlk a6
  .if \paramsize == 0
    rts
  .elseif \paramsize == 4
    move.l (sp)+,(sp)
    rts
  .else
    move.l (sp)+,a0
    .if \paramsize >= 1 && \paramsize <= 8
      addq.w #\paramsize,sp
    .else
      adda.w #\paramsize,sp
    .endif
    jmp (a0)
  .endif
.endm
