; asmsyntax=apricos
; ===================================
; ==                               ==
; ==   ApricotOS Display Library   ==
; ==                               ==
; ==          Revision 2           ==
; ==                               ==
; == (C) 2014-17 Nick Stones-Havas ==
; ==                               ==
; ==                               ==
; ==  Provides routines for        ==
; ==  controlling basic character  ==
; ==  mode displays.               ==
; ==                               ==
; ===================================
;
#name "libdisp"
#segment 8

#include "apricotosint.asm"
#include "portout.asm"
#include "math.asm"

#macro TTY_MODE mode treg {
    ASET treg
    LARl mode
    PORTOUT_TTY_WRITE
}

#macro PUTCHAR treg {
    ASET treg
    PORTOUT_TTY_WRITE
}

; Routine pointers
.nearptr PUTSTR
.nearptr PUTNUM
.nearptr TTYRESET

; Write a null terminated string to the display
; The input string is allowed to cross a segment boundary
; $a8 - memory block containing string
; $a9 - block local address of string
;
; Volatile registers:
; $a8
; $a9
; $a10
;
PUTSTR:
    ASET 8
    STah
    ASET 9
    STal

    PRINT_LOOP:
        ASET 10
        LD
        BRz PRINT_END
        PORTOUT_TTY_WRITE
        ASET 9
        ADD 1
        STal
        BRnp PRINT_LOOP

        ; An overflow occured, so increment the segment number
        ASET 8
        ADD 1
        STah
        JMP PRINT_LOOP
    PRINT_END:

    ; Return to caller
    ASET 8
    OS_SYSCALL_RET

; Write an 8 bit number to the display
; $a8 - The number to write
;
; Volatile registers:
; $a8
; $a9
; $a10
; $a11
PUTNUM:
    ASET 9
    LARl 100
    ASET 10
    OS_SYSCALL LIBMATH_DIV

    ASET 10
    BRz PUTNUM_SKIP_100
    SPUSH
    LARl DECTOCHAR_TABLE
    SPOP ADD
    STal
    LAh DECTOCHAR_TABLE
    LD
    PORTOUT_TTY_WRITE
    PUTNUM_SKIP_100:

    ASET 11
    SPUSH
    ASET 8
    SPOP
    ASET 9
    LARl 10
    ASET 10
    OS_SYSCALL LIBMATH_DIV

    ASET 10
    BRz PUTNUM_SKIP_10
    SPUSH
    LARl DECTOCHAR_TABLE
    SPOP ADD
    STal
    LAh DECTOCHAR_TABLE
    LD
    PORTOUT_TTY_WRITE
    PUTNUM_SKIP_10:

    ASET 11
    SPUSH
    LARl DECTOCHAR_TABLE
    SPOP ADD
    STal
    LAh DECTOCHAR_TABLE
    LD
    PORTOUT_TTY_WRITE

    OS_SYSCALL_RET

; Reset the TTY
;
; Volatile registers:
; $a8
;
TTYRESET:
    ; End any previous TTY command
    ASET 8
    AND 0
    ADD 3
    PORTOUT_TTY_WRITE ; End any previous TTY command


    ; Disable the cursor
    LARl 0x10   ; Cursor disable
    PORTOUT_TTY_WRITE
    AND 0
    PORTOUT_TTY_WRITE

    ; Clear the screen
    LARl 0x12   ; CLS
    PORTOUT_TTY_WRITE
    PORTOUT_TTY_WRITE

    OS_SYSCALL_RET

;
; ================
;   PUTNUM DATA
; ================
;
DECTOCHAR_TABLE:
.stringz '0123456789'
