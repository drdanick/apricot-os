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

#include "potatosinc.asm"

#macro TTY_MODE mode treg {
    ASET treg
    LAl mode
    LDal
    PRTout 7
}

#macro PUTCHAR treg {
    ASET treg
    PRTout 7
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
        PRTout 7
        ASET 9
        ADD 1
        STal
        BRnzp PRINT_LOOP
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
    PRTout 7   ; End any previous TTY command

    LAh 0x12   ; CLS
    LAl 0x10   ; Cursor disable

    ; Disable the cursor
    LDal
    PRTout 7
    AND 0
    PRTout 7

    ; Clear the screen
    LDah
    PRTout 7
    PRTout 7

    OS_SYSCALL_RET
