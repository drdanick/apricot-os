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
; ===================================
;
#name "libmath"
#segment 9 ; TODO: Pick a more appropriate segment number

#include "potatosinc.asm"
#include "osutil.asm"
#include "memutil.asm"

; Routine pointers
.nearptr MULT
.nearptr ATOB
.nearptr HTOI

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
        JMP MULT_LOOP_START
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
ATOB:
    ; TODO
    OS_SYSCALL_RET

; Convert a string of hex characters to a 16 bit integer.
; Note that no bounds checking is done.
; $a8 - Segment number of hex string in memory
; $a9 - Segment local address of hex string in memory
;
; Outputs:
; $a10 - Most significant byte of output number
; $a11 - Least significant byte of output number
;
; Volatile registers:
; $a9
; $a12
; $a13
; $a14
; $a15
;
HTOI:
    ; Zero hex bytes storage
    LAh TEMP_HEX_BYTES
    LAl TEMP_HEX_BYTES
    ASET 10
    LDal
    ASET 11
    AND 0
    ST
    ASET 10
    ADD 1
    STal
    ASET 11
    ST
    ASET 10
    ADD 1
    STal
    ASET 11
    ST
    ASET 10
    ADD 1
    STal
    ASET 11
    ST

    ASET 13   ; Zero the character counter
    AND 0

    ASET 14   ; Store negative value of '0' (to subtract from each hex character) 
    LAR 0x30  ; ASCII encoding of '0'
    NOT       ; Negate this value
    ADD 1

    ASET 15 ; Store the local address of the hex table in $a15
    LARl HEX_TABLE

    HTOI_READ_LOOP:
        ASET 8   ; Set segment address of next hex digit to load
        STah
        ASET 9   ; Segment local address of next hex digit
        STal
        ADD 1

        ASET 12  ; Store next hex digit in $a12
        LD

        ; If the digit is zero, skip to the processing phase...
        BRz HTOI_READ_LOOP_END

        ; ...otherwise, convert it to its integer representation...
        ASET 14
        SPUSH
        ASET 12
        SPOP ADD

        ; ...then convert the number to an index in the hex lookup table by adding the table's base address...
        ASET 15
        SPUSH
        ASET 12
        SPOP ADD

        ;...and finally, get the value in the table at the calculated index, push it to the stack, and increment the character read counter.
        STal
        LAh HEX_TABLE
        LD
        SPUSH

        ASET 13
        ADD 1

        JMP HTOI_READ_LOOP ; Move on to the next character
    HTOI_READ_LOOP_END:
    
    ASET 14 ; Store the value of -1 in $a14
    LAR 0xFF

    ; Set up $mar with the address of the last digit of hex storage
    LAh TEMP_HEX_BYTES
    ASET 11
    LARl TEMP_HEX_BYTES
    ADD 3
    STal

    ; Pop digits from the stack and put them in memory
    HTOI_STACK_TO_MEM_LOOP:
        ASET 13
        BRnz HTOI_STACK_TO_MEM_LOOP_END  ; Finish if our character counter is zero
        ASET 14  ; Derement the character counter
        SPUSH
        SPUSH    ; This second push is for the hex address decrement
        ASET 13
        SPOP ADD

        ASET 11  ; Decrement the hex array local address (dont store it into $mar yet)
        SPOP ADD

        ASET 12 ; Pop the next digit into $a12
        SPOP
        ST      ; Store it to the end of the hex array

        ASET 11 ; Set the address of the next storage position into $mar
        STal

        JMP HTOI_STACK_TO_MEM_LOOP ; Continue with loop
    HTOI_STACK_TO_MEM_LOOP_END:

    ASET 12
    LARl TEMP_HEX_BYTES
    STal

    ; Load the most significant byte
    ASET 10
    LD
    SHFl 4
    SPUSH
    ASET 12
    ADD 1
    STal
    ASET 10
    LD
    SPOP OR

    ; Load the least significant byte
    ASET 12
    ADD 1
    STal
    ASET 11
    LD
    SHFl 4
    SPUSH
    ASET 12
    ADD 1
    STal
    ASET 11
    LD
    SPOP OR

    ASET 12
    OS_SYSCALL_RET


TEMP_HEX_BYTES: .blockw 4 0  ; Temporary storage for hex->integer conversion

HEX_TABLE:
.fill 0   ; 0
.fill 1   ; 1
.fill 2   ; 2
.fill 3   ; 3
.fill 4   ; 4
.fill 5   ; 5
.fill 6   ; 6
.fill 7   ; 7
.fill 8   ; 8
.fill 9   ; 9
.fill 0   ; :
.fill 0   ; ;
.fill 0   ; <
.fill 0   ; =
.fill 0   ; >
.fill 0   ; ?
.fill 0   ; @
.fill 10  ; A
.fill 11  ; B
.fill 12  ; C
.fill 13  ; D
.fill 14  ; E
.fill 15  ; F
