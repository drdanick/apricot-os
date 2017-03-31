; asmsyntax=apricos
; ===================================
; ==                               ==
; ==   ApricotOS shell utilities   ==
; ==                               ==
; ==          Revision 1           ==
; ==                               ==
; == (C) 2014-17 Nick Stones-Havas ==
; ==                               ==
; ==                               ==
; ==  Provides utility functions   ==
; ==  for the ApricotOS shell.     ==
; ==                               ==
; ===================================
;
#name "shellutil"
#segment 13

#include "apricotosint.asm"
#include "shellmem.asm"
#include "shellcmds.asm"
#include "disp.asm"
#include "osutil.asm"
#include "portout.asm"
#include "portin.asm"

.nearptr PRINTPROMPT
.nearptr READLINE

;
; Prints the prompt string
;
; Volatile registers:
; $a8
; $a9
; $a10
;
PRINTPROMPT:
    ASET 8
    LARh SHELLMEM_PROMPT
    ASET 9
    LARl SHELLMEM_PROMPT

    ASET 10
    OS_SYSCALL LIBDISP_PUTSTR

    OS_SYSCALL_RET

;
; Get a line of input from the user.
;
; Return values:
; $a13 - The segment number of the inputted line
; $a14 - The segment local address of the inputted line
; $a15 - The length of the inputted line
;
; Notes:
; -The maximum line length is 128. Characters 
; entered after this limit is reached are ignored.
; -The TTY mode will be reset by this routine.
;
; Volatile registers:
; $a8
; $a9
; $a10
; $a11
; $a12
; $a13
; $a14
; $a15
;
READLINE:
    OS_SYSCALL OSUTIL_PUSHREGS

    ; Reset the TTY and put it into line mode
    AND 0
    ADD 3
    PORTOUT_TTY_WRITE
    LARl 0x7F
    PORTOUT_TTY_WRITE
    AND 0
    PORTOUT_TTY_WRITE


    ; Set up constant values in registers
    ASET 0
    LARl 0x60  ; Mask to check for valid printable characters

    ASET 1
    LARl 0x20  ; Uppercase/lowercase toggle bit

    ASET 2
    LARl 0x41  ; ASCII encoding of 'A'
    NOT       ; Negate this value
    ADD 1

    ASET 3
    LARl 0x5A  ; ASCII encoding of 'Z'
    NOT       ; Negate this value
    ADD 1

    ASET 4
    LARl 0x0A  ; ASCII linefeed

    ASET 5
    LARl 0x08  ; ASCII backspace

    ASET 6
    LARl 0x7F  ; ASCII delete

    ASET 7
    LARl 0xFF  ; -1

    ASET 9    ; $a9 points to the address directly following the buffer
    LARl SHELLMEM_CMDBUFFEND

    LAh SHELLMEM_CMDBUFF
    LAl SHELLMEM_CMDBUFF
    ASET 13   ; $a15 points to the segment number of the buffer
    LDah
    ASET 14   ; $a14 points at the next free space in the input buffer
    LDal

    ASET 15   ; $a15 holds the length of the input
    AND 0


    ; Input processing steps:
    ; 1) Get a character from the keyboard
    ; 2) Check if the character is a newline, backspace or DEL, react accordingly
    ; 3) Make sure there is room in the buffer. If not, go back to 1
    ; 4) Make sure the most significant 3 bits are non-zero (discard otherwise)
    ; 5) Unassert the 3rd most significant bit, and check if the character is between A and Z. Reassert the bit if it is not.
    ; 6) Append the character to the buffer
    ; 7) Print the character
    ; 8) Repeat the process

    ; NOTES: 
    ; - The following loop assumes that $mar points at the segment containing the buffer
    ; - $a10 is used as a temporary register in the following loop

    RL_LOOP_START:
        ASET 8   ; $a8 will hold the character while it is being processed

        PORTIN_KBD_INPUT ; Get the character
        
        SPUSH            ; Save the character 

        ; Check for newline
        ASET 4
        SPUSH
        ASET 8
        SPOP XOR
        BRz DO_NEWLINE

        SPOP     ; Restore and backup the character
        SPUSH

        ; Check for backspace
        ASET 5
        SPUSH
        ASET 8
        SPOP XOR
        BRz DO_BACKSPACE

        SPOP     ; Restore and backup the character
        SPUSH

        ; Check for delete
        ASET 6
        SPUSH
        ASET 8
        SPOP XOR
        BRz DO_BACKSPACE

        SPOP    ; Restore the character

        ; Check that there is room in the buffer (next free space should not be the same address as the end-of-buffer marker)
        ; If it is, return to the start of the loop
        ASET 14
        SPUSH
        ASET 9
        SPUSH
        ASET 10
        SPOP
        SPOP XOR
        BRz RL_LOOP_START

        ; Check that the character is a valid, printable character
        ASET 8  ; Save the character onto the stack
        SPUSH
        ASET 0 
        SPUSH
        ASET 10
        SPOP
        SPOP AND ; Apply the mask
        BRz RL_LOOP_START

        ; Unassert the lowercase bit, and check if the character is in the range of A-Z
        ASET 8
        SPUSH
        SPUSH   ; Keep an extra copy of the character on the stack
        ASET 1
        SPUSH
        ASET 8
        SPOP
        NOT
        SPOP AND ; Mask out the lowercase bit
        SPUSH

        ; Check if the character is greater than 'A'
        ASET 2
        SPUSH
        ASET 10
        SPOP
        SPOP ADD
        BRn NOT_ALPHA_CHAR

        ; Check if the character is less than 'Z'
        ASET 8
        SPUSH
        ASET 3
        SPUSH
        ASET 10
        SPOP
        SPOP ADD
        BRp NOT_ALPHA_CHAR

        ; At this point, we know the character is an uppercase letter. Dump the backup remaining in the stack and continue
        ASET 10
        SPOP
        ASET 8
        JMP SAVE_CHAR

        NOT_ALPHA_CHAR:
        ASET 8  ; Restore the old character value
        SPOP
        SPUSH
        ASET 10
        SPOP

        SAVE_CHAR:
        ; $mar should be pointing at the next free space in the buffer, so just store the character there.
        ST

        ; Echo the character
        ASET 10
        PORTOUT_TTY_WRITE

        ; Increment the input length and buffer pointer
        ASET 14
        ADD 1
        STal
        ASET 15
        ADD 1

        JMP RL_LOOP_START
        DO_BACKSPACE:
        SPOP
        ASET 15
        BRz RL_LOOP_START  ; Don't do anything if the buffer is already empty
        
        ; Decrement the length counter and the pointer
        ASET 7  ; (-1)
        SPUSH
        SPUSH
        ASET 15
        SPOP ADD
        ASET 14
        SPOP ADD
        STal

        ; Print a backspace char to the terminal
        ASET 5
        PORTOUT_TTY_WRITE

        JMP RL_LOOP_START
        DO_NEWLINE:
        ASET 4
        PORTOUT_TTY_WRITE
        SPOP    ; Dump the previously saved character
    RL_LOOP_END:

    ; Write a NUL character to the end of the buffer
    ASET 14
    STal
    ASET 10
    AND 0
    ST

    ; Set the remaining return values
    ASET 14
    LARl SHELLMEM_CMDBUFF

    ASET 8
    OS_SYSCALL OSUTIL_POPREGS
    OS_SYSCALL_RET
