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

#macro PUTNEWLINE {
    LARl 10
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
    ASET 9
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

; Write a 16 bit unsigned number to the display in decimal
; (no leading zeros)
; $a8 - The high byte of the number
; $a9 - The low byte of the number
;
; Volatile registers:
; $a8 - $a15
;
; Makes no calls. For each power of ten it counts how many times the power
; can be subtracted (repeated trial subtraction), then prints that digit.
;
; Registers:
; $a8:$a9   - what is left of the number
; $a10:$a11 - the current negated power of ten
; $a12      - the current digit
; $a13      - non-zero once a digit has been printed
; $a14      - power table pointer / scratch; $a15 scratch
;
PUTNUM16:
    ASET 13            ; $a13 = non-zero once a digit has been printed
    AND 0
    ASET 14
    LARl P16_POWERS
    SPUSH              ; The power table pointer lives on the stack

    P16_POWER:
        ; $a10:$a11 = the next negated power of ten (high byte 0 = end)
        ASET 14
        SPOP
        SPUSH
        STal
        LAh P16_POWERS
        ASET 10
        LD
        BRz P16_LAST
        ASET 14
        ADD 1
        STal
        ASET 11
        LD
        ASET 12        ; $a12 = digit
        AND 0

        P16_TRY:
            ; Trial subtraction: ($a8:$a9) + ($a10:$a11). It carries out
            ; exactly when the number is >= the power.
            ASET 9
            SPUSH
            ASET 11
            SPUSH
            ASET 14
            SPOP
            SPOP ADD       ; low byte sum, O = carry 1
            SPUSH
            PRTin 4
            SHFr 3         ; $a14 = carry 1
            ASET 10
            SPUSH
            ASET 8
            SPUSH
            ASET 15
            SPOP
            SPOP ADD       ; high byte sum, O = carry A
            SPUSH
            PRTin 4
            SHFr 3         ; $a15 = carry A
            ASET 14
            SPOP ADD       ; high byte sum + carry 1, O = carry B
            SPUSH
            PRTin 4
            SHFr 3         ; $a14 = carry B
            ASET 15
            SPUSH
            ASET 14
            SPOP OR        ; Carry out of the 16 bit addition
            BRz P16_TRY_FAIL

            ASET 8         ; Keep the difference and count the digit
            SPOP
            ASET 9
            SPOP
            ASET 12
            ADD 1
            JMP P16_TRY

        P16_TRY_FAIL:
        SPOP
        SPOP

        ; Print the digit, unless it is a leading zero
        ASET 12
        BRnp P16_PRINT
        ASET 13
        BRz P16_NEXT
        P16_PRINT:
        ASET 13
        OR 1
        ASET 12
        SPUSH
        ASET 14
        LARl 0x30
        SPOP ADD
        PORTOUT_TTY_WRITE

        P16_NEXT:
        ASET 14
        SPOP
        ADD 2
        SPUSH
        JMP P16_POWER

    P16_LAST:
    ASET 14
    SPOP
    ASET 9             ; The remaining units digit is always printed
    SPUSH
    ASET 14
    LARl 0x30
    SPOP ADD
    PORTOUT_TTY_WRITE

    ASET 14
    OS_SYSCALL_RET

; -10000, -1000, -100, -10 as 16 bit values (high byte first), then 0.
; Must not cross a page (PUTNUM16 keeps only the low byte of its pointer).
P16_POWERS:
.fill 0xD8
.fill 0xF0
.fill 0xFC
.fill 0x18
.fill 0xFF
.fill 0x9C
.fill 0xFF
.fill 0xF6
.fill 0x00

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
