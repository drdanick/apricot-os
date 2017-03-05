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
#segment 7

#include "apricotosint.asm"
#include "portout.asm"

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
.nearptr TTYRESET

; Write a null terminated string to the display
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
        JMP PRINT_LOOP
    PRINT_END:

    ; Return to caller
    ASET 8
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
