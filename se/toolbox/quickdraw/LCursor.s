| ------------------------------------------------------------------
|
| --> LCURSOR.TEXT
|
| Links to MacIntosh Cursor routines.
|
| System Graphic Jump Vectors:
|
| Long pointers to system routine entry points.

| ----------------------------------------------------------
| INITCURSOR ($A850) - install standard arrow cursor and call jump
| Pascal: procedure InitCursor;
| Sets cursor to ARROW (QD globals at -0x6C(qdGlobals)) then jumps
| through JInitCrsr lowmem trampoline so a patched extension can
| post-process.
INITCURSOR:
    MOVEA.L	(A5),A0                             | A0 -> QD globals
    PEA.L	-0x6C(A0)                             | push @ARROW (cursor data)
    JSR	SETCURSOR(PC)                           | install ARROW
    MOVEA.L	(JInitCrsr).W,A0                    | A0 = JInitCrsr trampoline
    JMP	(A0)                                    | tail-call to extension
| ----------------------------------------------------------
| SETCURSOR ($A851) - install caller's cursor through JSetCrsr
| Pascal: procedure SetCursor(crsr: Cursor);
| Cursor record (68 bytes): 32 data + 32 mask + Point hotSpot.
SETCURSOR:
    MOVEA.L	0x4(A7),A0                          | A0 -> caller's Cursor
    MOVE.L	0x40(A0),-(A7)                       | push hotSpot.h:hotSpot.v
    MOVE.W	#0x10,-(A7)                          | height = 16 rows
    PEA.L	(A0)                                  | push @data
    PEA.L	0x20(A0)                              | push @mask (data + 32)
    MOVEA.L	(JSetCrsr).W,A0                     | A0 = JSetCrsr trampoline
    JSR	(A0)                                    | call vector
    MOVE.L	(A7)+,(A7)                           | drop one param, replace ret addr
    RTS                                         | return from SETCURSOR
| ----------------------------------------------------------
| HIDECURSOR ($A852) - hide cursor via JHideCursor lowmem vector
| Pascal: procedure HideCursor;
HIDECURSOR:
    MOVE.L	(GrafBegin_JHideCursor).W,-(A7)      | push trampoline as ret addr
    RTS                                         | jump to JHideCursor
| ----------------------------------------------------------
| SHOWCURSOR ($A853) - show cursor via JShowCursor lowmem vector
| Pascal: procedure ShowCursor;
| Called by: GETPIXEL, STRDONE, DRAWLINE_DONE, RGNBLT_DONE, DRAWARC_DONE (and 4 more)
SHOWCURSOR:
    MOVE.L	(JShowCursor).W,-(A7)                | push trampoline as ret addr
    RTS                                         | jump to JShowCursor
| ----------------------------------------------------------
| SHIELDCURSOR ($A855) - hide cursor while drawing inside rect
| Pascal: procedure ShieldCursor(shieldRect: Rect; offset: Point);
| Translates global rect by offset, calls JShieldCursor with the
| 4 separate coords (left,top,right,bottom) on stack.
| Called by: VCLIP_NO, VOK2_NO, RGNBLT, SOLID, COPYBITS (and 2 more)
SHIELDCURSOR:
    MOVEM.L	D0-D3/A0-A1,-(A7)                   | save regs
    MOVEA.L	0x20(A7),A0                         | A0 -> shieldRect
    MOVEM.W	(A0)+,D0-D3                         | D0..D3 = top, left, bot, right
    LEA.L	0x1C(A7),A1                           | A1 -> offset (Point)
    SUB.W	(A1),D0                               | top -= offset.v
    SUB.W	(A1)+,D2                              | bot -= offset.v
    SUB.W	(A1),D1                               | left -= offset.h
    SUB.W	(A1),D3                               | right -= offset.h
    MOVE.W	D1,-(A7)                             | push left
    MOVE.W	D0,-(A7)                             | push top
    MOVE.W	D3,-(A7)                             | push right
    MOVE.W	D2,-(A7)                             | push bottom
    MOVEA.L	(JShieldCursor).W,A0                | A0 = JShieldCursor trampoline
    JSR	(A0)                                    | call vector
    MOVEM.L	(A7)+,D0-D3/A0-A1                   | restore regs
    MOVE.L	(A7)+,(A7)                           | strip 4 bytes (Rect param)
    MOVE.L	(A7)+,(A7)                           | strip 4 more (Point param)
    RTS                                         | return from SHIELDCURSOR
| ----------------------------------------------------------
| OBSCURECURSOR ($A856) - hide cursor until mouse moves
| Pascal: procedure ObscureCursor;
OBSCURECURSOR:
    MOVEA.L	(JCrsrObscure).W,A0                 | A0 = JCrsrObscure trampoline
    JMP	(A0)                                    | tail-call vector
