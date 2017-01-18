; asmsyntax=apricos
; ===================================
; ==                               ==
; ==    ApricotOS Math Library     ==
; ==                               ==
; ==          Revision 1           ==
; ==                               ==
; ==  (C) 2017  Nick Stones-Havas  ==
; ==                               ==
; ==                               ==
; ==  Provides routines for        ==
; ==  basic arithmetic.            ==
; ==                               ==
; ==                               ==
; ===================================
;
#name "libmath"
#segment 20 ; TODO: Pick a more appropriate segment number

#include "potatosinc.asm"

; Routine pointers
.nearptr MULT
.nearptr ATOI

; Multiply two numbers together
; $a8 - the first operand to multiply
; $a9 - the second operand to multiply
;
; Outputs:
; $a10 - the result
;
; Volatile registers:
; $a9
; $a11
;
MULT:
    ; Zero the result
    ASET 10
    AND 0

    ; Negate the second operand (to use it as a counter)
    ASET 9
    NOT
    ADD 1

    ; Continuously add the value that is on the stack
    ; to $a10 until the counter reaches 0
    MULT_LOOP_START:
        BRzp MULT_LOOP_END

        ; Place the first operand on the stack...
        ASET 8
        SPUSH

        ; ...and add it to the result
        ASET 10
        SPOP ADD

        ASET 9
        ADD 1
        BRnzp MULT_LOOP_START
    MULT_LOOP_END:

    OS_SYSCALL_RET


; Convert a string of numeric characters to an 8bit integer.
; Note that no bounds checking is done.
; $a8 - Segment number of numeric string in memory
; $a9 - Segment local address of numeric string in memory
;
; Outputs:
; $a10 - The resulting 8 bit number
;
; Volatile registers:
; 
ATOI:
    OS_SYSCALL_RET
