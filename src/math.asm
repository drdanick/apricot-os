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

#include "apricotosint.asm"
#include "osutil.asm"
#include "memutil.asm"
#include "portin.asm"

;
; ==============
; MACROS
; ==============
;


; Subtract two numbers
; reg1 - the first operand
; reg2 - the second operand
;
; Output:
; reg1 - the result of the subtraction
;
#macro SUB reg1 reg2 {
    ASET reg2
    NOT
    ADD 1
    SPUSH
    ASET reg1
    SPOP ADD
}


;
; ==============
; ROUTINES
; ==============
;

; Routine pointers
.nearptr MULT
.nearptr DIV
.nearptr ATOB
.nearptr HTOI

; Multiply two numbers together.
; Both operands are treated as unsigned.
; $a8 - the first operand to multiply
; $a9 - the second operand to multiply
;
; Outputs:
; $a10 - the result
; $a11 - non-zero if an overflow occured, zero otherwise
;
; Volatile registers:
; $a9
; $a11
;
MULT:
    ; Zero the results
    ASET 10
    AND 0

    ASET 11
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
        OVERFLOW_CHECK:

        ; Check for overflows
        SPUSH
        PORTIN_STATUS_REG
        SHFr 3
        BRz NO_MULT_OVERFLOW

        ; An overflow occured
        ASET 11
        OR 1
        ASET 10

        NO_MULT_OVERFLOW:
        SPOP
        ASET 9
        ADD 1
        JMP MULT_LOOP_START
    MULT_LOOP_END:

    OS_SYSCALL_RET

; Perform integer division between two numbers.
; Both operands are treated as unsigned.
; $a8 - the dividend to divide
; $a9 - the divisor
;
; Outputs:
; $a10 - the result of integer division. aka, the result of %a8 / %a9
; $a11 - the remainder. aka, the result of $a8 MOD $a9.
;
; Volatile registers:
; $a8
;
DIV:
    ; zero the division result. (remainder is always overwritten, so no need to zero)
    ASET 10
    AND 0

    ; Store the divisor on the stack so we can obtain the
    ; remainder at the end
    ASET 9
    SPUSH

    ; Negate the divisor so we can continuously subtract it
    NOT
    ADD 1
    DIV_LOOP:
        SPUSH
        ASET 8
        SPOP ADD
        BRn DIV_LOOP_END
        ASET 10
        ADD 1
        ASET 9
        JMP DIV_LOOP
    DIV_LOOP_END:

    ; Calculate remainder by adding our saved divisor and
    ; the result of our division loop (stored in $a8).
    ASET 8
    SPUSH
    ASET 11
    SPOP
    SPOP ADD

    ASET 8
    OS_SYSCALL_RET


; Convert a string of numeric characters to an 8bit integer.
; Note that no bounds checking is done.
; $a8 - Segment number of numeric string in memory
; $a9 - Segment local address of numeric string in memory
;
; Outputs:
; $a10 - Non-zero if the operation succeeded, 0 otherwise.
; $a11 - The resulting 8 bit number.
;
; Volatile registers:
; $a9
; $a10
; $a11
; $a12
; $a13
; $a14
; $a15
;
ATOB:
    ; We're using $a0 in this routine, so store it on the stack before we do anything else
    ASET 0
    SPUSH

    ; Then set it to be zero
    AND 0

    ; We need the length of the string to figure out what decimal weight to start with
    ASET 15
    OS_SYSCALL MEMUTIL_STRLEN

    ; Assume an error occured until we know otherwise
    ASET 10
    AND 0

    ; Zero the result
    ASET 11
    AND 0

    ; $a13 will hold our decimal weight
    LDI ATOB_WEIGHT_TABLE
    ASET 13
    SPUSH
    LDal
    SPOP ADD
    STal
    LD
    SPUSH


    ; Set $a14 to be the -ve of the maximum length we allow
    ASET 14
    LARl 0xFD ; -3

    ; Subtract -3 from the calculated length. If it's negative, the length is longer than we support, so return in error.
    ; No need to zero $a10, this has already been done
    SPOP ADD
    BRn ATOB_RETURN

    ; ...Otherwise, we process the input string:
    ;
    ; Variables for this code:
    ; $a0: The final result
    ; $a8: The current decimal weight
    ; $a14: The current character segment local address
    ; $a15: -48, the value we subtract from each input number
    ;

    ; Move segment local address of string into $a9
    ASET 9
    SPUSH
    ASET 14
    SPOP

    ASET 15
    LARl 0xD0 ; -48

    ASET 13
    SPUSH ; Put the current decimal weight onto the stack
    ASET 8
    STah      ; Set up $mar segment to point to the input string
    ATOB_LOOP:
        ASET 14 ; Read the next character
        STal
        ADD 1  ; Advance to next character for next iteration

        ASET 15
        SPUSH

        ; Load the next digit character and convert it to an integer
        ASET 9
        LD
        SPOP ADD

        ; Multiply input integer by the current decimal weight
        ASET 8
        SPOP
        SPUSH ; ...but keep the weight on the stack
        ASET 10
        OS_PUSH_MAR
        OS_SYSCALL MULT
        OS_POP_MAR

        ; Next, we add this to our result
        ASET 10
        SPUSH
        ASET 0
        SPOP ADD
        SPUSH

        ; Check for overflow in either mult routine or the last addition
        PORTIN_STATUS_REG
        SHFr 3
        SPUSH
        ASET 11
        SPOP OR
        BRnp ATOB_LOOP_ERROR

        ASET 0
        SPOP

        ; Next, we divide the current decimal weight by 10
        ASET 8
        SPOP

        ASET 9
        LARl 10

        ; Call the div routine
        ASET 10
        OS_PUSH_MAR
        OS_SYSCALL DIV
        OS_POP_MAR

        ; If our weight is zero, break from the loop
        ASET 10
        SPUSH ; Push the result to the stack
        BRz ATOB_LOOP_SUCCESS

        JMP ATOB_LOOP
    ATOB_LOOP_ERROR:
        ASET 10
        SPOP ; Remove residual result from stack
        AND 0
        JMP ATOB_LOOP_CLEANUP
    ATOB_LOOP_SUCCESS:

    ; If we got to this point, no error occured
    ASET 10
    OR 1

    ; Move result into $a11
    ASET 0
    SPUSH
    ASET 11
    SPOP

    ATOB_LOOP_CLEANUP:

    ; Pop off residual values from stack
    ASET 15
    SPOP ; The decimal weight

    ATOB_RETURN:

    ; Restore $a0
    ASET 0
    SPOP

    ASET 15
    OS_SYSCALL_RET


; ATOB Weight table
ATOB_WEIGHT_TABLE:
.fill 0
.fill 1
.fill 10
.fill 100

; ================================
;         SEGMENT BOUNDARY
; ================================
.padseg 0

; Raise a base number to the power of an exponent.
; $a8 - The base
; $a9 - The power
;
; Outputs:
; $a10 - The result
; $a11 - non-zero if an overflow occured, zero otherwise
;
; Volatile registers:
; $a9
; $a11
; $a12
; $a14
; $a15
;
POW:
    ; Zero the overflow register (using 12 for this until we have our final result)
    ASET 12
    AND 0

    ; Move base to the stack and set result to 1
    ASET 8
    SPUSH
    LARl 1

    ; Move $a9 to $a15 so it's not disturbed by MULT
    ASET 9
    SPUSH
    ASET 15
    SPOP

    BRz POW_LOOP_END
    POW_LOOP:
        ; Pop base into $a9
        ASET 9
        SPOP

        ; Keep base on the stack for later
        SPUSH

        ; Call MULT
        ASET 14
        OS_LOCALSYSCALL MULT

        ; Move the overflow flag into $a12
        ASET 11
        SPUSH
        ASET 12
        SPOP OR

        ; Move the mult result from $a10 to $a8
        ASET 10
        SPUSH
        ASET 8
        SPOP

        ; Subtract 1 from counter and break if zero
        ASET 15
        SPUSH
        LARl 0xFF ; equivalent to -1
        SPOP ADD
        BRnp POW_LOOP
    POW_LOOP_END:

    ; Move our result from $a8 to $a10
    ASET 8
    SPUSH
    ASET 10
    SPOP

    ; Move the overflow result from $a12 to $a11
    ASET 12
    SPUSH
    ASET 11
    SPOP

    ASET 9
    SPOP ; Clear base from the stack
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
