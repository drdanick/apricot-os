; asmsyntax=apricos
; ===================================
; ==                               ==
; ==    ApricOS memory utility     ==
; ==    routines                   ==
; ==                               ==
; ==          Revision 1           ==
; ==                               ==
; ==  (C) 2014  Nick Stones-Havas  ==
; ==                               ==
; ==                               ==
; ==  Provides a collection of     ==
; ==  memory utility routines.     ==
; ==                               ==
; ===================================
;
#name "memutil"
#segment 0x05

#include "potatosinc.asm"

; Function pointers
;.nearptr SEGCPY
;.nearptr SEGSET
;.nearptr MEMCPY
;.nearptr MEMSET
;.nearptr MEMCMP
;.nearptr STRLEN
;;.nearptr STRCPY
;.nearptr STRCMP

;
; Copies a segment of memory to another segment. 
; $a8 - The source segment number
; $a9 - The destination segment number
;
; Volatile registers:
; $a8
; $a10
; $a11
;
SEGCPY:
    ASET 10 ; Use $a10 to hold the segment local address of the current byte
    AND 0

    SEGCPYLP:
        STal
        ASET 8
        STah
        ASET 11
        LD
        ASET 9
        STah
        ASET 11
        ST
        ASET 10
        ADD 1
    BRnp SEGCPYLP

    OS_SYSCALL_RET

;
; Sets all bytes in a given segment to a given value.
; $a8 - The segment number to set
; $a9 - The value to set
;
; Volatile registers:
; $a10
;
SEGSET:
    ASET 8
    STah
    ASET 10
    AND 0

    SEGSET_LOOP:
        STal
        ASET 9
        ST
        ASET 10
        ADD 1
        BRnp SEGSET_LOOP

    OS_SYSCALL_RET

;
; Copies a block of memory of a given size from a starting 
; memory address, to a destination memory address.
; $a8  - The source segment number
; $a9  - The source segment local address
; $a10 - The destination segment number
; $a11 - The destination segment local address
; $a12 - The number of bytes to copy
;
; Notes:
; - The source and destination blocks are permitted to 
; cross a segment boundary.
;
; Volatile registers:
; $a8
; $a9
; $a10
; $a11
; $a12
; $a13
;
MEMCPY:
    ASET 12 ; Negate the counter (2s complement)
    NOT
    ADD 1
    MEMCPYLP:
        BRz MEMCPYLP_END ; Break if the counter is zero

        ASET 8  ; Set up the source address
        STah
        ASET 9
        STal
        ADD 1   ; Increment the source address and increment the segment number if it overflows

        BRnp MCPY_SRC_NOOVERFLOW
        ASET 8
        ADD 1
        MCPY_SRC_NOOVERFLOW:

        ASET 13          ; Load the next byte from the source
        LD

        ASET 10          ; Set up the destination address
        STah
        ASET 11
        STal
        ADD 1            ; Increment the destination address and increment the segment number if it overflows

        BRnp MCPY_DST_NOOVERFLOW
        ASET 10
        ADD 1
        MCPY_DST_NOOVERFLOW:

        ASET 13          ; Store the byte
        ST

        ASET 12          ; Decrement the counter
        ADD 1
        BRnzp MEMCPYLP
    MEMCPYLP_END:

    OS_SYSCALL_RET

;
; Sets all bytes in a given block of memory of a given 
; size to a given value.
; $a8  - The segment number of the block of memory
; $a9  - The segment local address of the block of memory
; $a10 - The size of the block
; $a11 - The value to set
;
; Notes:
; - The source and destination blocks are permitted to 
; cross a segment boundary.
;
; Volatile registers:
; $a8
; $a9
; $a10
;
MEMSET:
    ASET 10   ; Negate the counter (2s complement)
    NOT
    ADD 1

    MEMSET_LP:
        BRz MEMSET_LP_END ; Break if the counter is zero

        ASET 8  ; Set up the destination address
        STah
        ASET 9
        STal
        ADD 1   ; Increment the destination address and increment the segment number if it overflows

        BRnp MSET_DST_NOOVERFLOW
        ASET 8
        ADD 1
        MSET_DST_NOOVERFLOW:

        ASET 11 ; Store the given value at the current address
        ST

        ASET 10 ; Decrement the counter
        ADD 1
        BRnp MEMSET_LP
    MEMSET_LP_END:
    
    OS_SYSCALL_RET

; Compares 2 blocks of memory and returns a positive integer if 
; they are equal, and 0 otherwise.
; $a8  - The segment number of the first block of memory
; $a9  - The segment local address of the first block of memory
; $a10 - The segment number of the second block of memory
; $a11 - The segment local address of the second block of memory
; $a12 - The size of the blocks
;
; Return values:
; $a13 - A positive integer if the blocks are equal, 0 otherwise.
;
; Notes:
; - The source and destination blocks are permitted to 
; cross a segment boundary.
;
; Volatile registers:
; $a8
; $a9
; $a10
; $a11
; $a12
; $a13
; $a14
;
MEMCMP:
    ASET 13  ; Start by assuming the two blocks are equal
    AND 0
    ADD 1

    ASET 12  ; Negate the counter (2s complement)
    NOT
    ADD 1

    MEMCMP_LP:
        BRz MEMCMP_LP_END_EQ

        ; Load a byte from the first string
        ASET 8
        STah
        ASET 9
        STal
        ADD 1

        BRnp MEMCMP_1_NOOVERFLOW
        ASET 8
        ADD 1
        MEMCMP_1_NOOVERFLOW:

        ASET 14
        LD
        SPUSH

        ; Load a byte from the second string
        ASET 10
        STah
        ASET 11
        STal
        ADD 1

        BRnp MEMCMP_2_NOOVERFLOW
        ASET 10
        ADD 1
        MEMCMP_2_NOOVERFLOW:

        ASET 14
        LD

        ; Do the comparison (XOR with the last byte), and break if the result is non-zero
        SPOP XOR
        BRnp MEMCMP_LP_END_NEQ

        ASET 12
        ADD 1
        BRnzp MEMCMP_LP
    MEMCMP_LP_END_NEQ:
    ASET 13
    AND 0
    MEMCMP_LP_END_EQ:

    ASET 14
    OS_SYSCALL_RET

;
; Calculates the length of a character string.
; $a8 - The segment number of the string.
; $a9 - The segment local address of the string.
;
; Return values:
; $a13 - The length of the given string
;
; Notes:
; - The string is permitted to cross a segment boundary
;
; Volatile registers:
; $a12
; $a13
; $a14 (only if the string crosses a segment boundary)
; $a15
;
STRLEN:
    ASET 13
    LAl 0xFF  ; Initialize the return value as -1 (since we always increment this regardless of whether it is an empty string)
    LDal

    ASET 8
    STah
    SPUSH
    ASET 9
    STal
    SPUSH


    ASET 15
    SPOP
    ASET 14
    SPOP

    STRLENLP:
        ASET 13
        ADD 1
        ASET 12
        LD
        ASET 15
        ADD 1
        STal
        BRnp STRLENLP_NOOVERFLOW
        ASET 14
        ADD 1
        STah
        STRLENLP_NOOVERFLOW:
        ASET 12
        BRnp STRLENLP

    OS_SYSCALL_RET

;
; Copies a string from a given source address to a given
; destination address.
; $a8  - The source segment number
; $a9  - The source segment local address
; $a10 - The destination segment number
; $a11 - The destination segment local address
;
; Notes:
; - The source and destination strings are permitted to 
; cross a segment boundary.
;
; Volatile registers:
; $a8
; $a9
; $a10
; $a11
; $a12
; $a13
;
;STRCPY:
    ; Push the registers that may not be preserved by STRLEN
;    ASET 8
;    SPUSH
;    ASET 9
;    SPUSH
;    ASET 10
;    SPUSH
;    ASET 11
;    SPUSH
;
;    OS_LOCALSYSCALL STRLEN
;    ASET 10
;    ADD 1  ; Account for the null terminator
;    SPUSH
;    ASET 12
;    SPOP 
;
;    ; Restore the registers as required by MEMCPY
;    ASET 11
;    SPOP
;    ASET 10
;    SPOP
;    ASET 9
;    SPOP
;    ASET 8
;    SPOP
;
;    ASET 13
;    OS_LOCALSYSCALL MEMCPY
;
;    OS_SYSCALL_RET

;
; Compares two strings and returns a positive integer 
; if they are equal, and 0 if they are not.
; $a8  - The segment number of the first string
; $a9  - The segment local address of the first string
; $a10 - The segment number of the second string
; $a11 - The segment local address of the second string
;
; Return values:
; $a13 - A positive integer if the strings are equal, 0 otherwise.
;
; Notes:
; The strings are permitted to cross segment boundaries.
;
; Volatile registers:
; $a12
; $a13
; $a14
;
STRCMP:
    ; Backup the argument registers so they are preserved accross the syscall
    ASET 11
    SPUSH
    ASET 10
    SPUSH
    ASET 9
    SPUSH
    ASET 8
    SPUSH

    ; Preserve $a8 and $a9
    SPUSH
    ASET 9
    SPUSH

    ; Get the length of the first string
    ASET 13
    OS_LOCALSYSCALL STRLEN

    ; Set up the registers to get the length of the second string
    ASET 11
    SPUSH
    ASET 10
    SPUSH
    ASET 8
    SPOP
    ASET 9
    SPOP
    ASET 13 ; Preserve the length of the first stirng
    SPUSH
    SPUSH

    ; Get the length of the second string
    OS_LOCALSYSCALL STRLEN

    ; XOR the length of the first string with the length of the second string
    ASET 13
    SPUSH
    AND 0
    ASET 14
    SPOP
    SPOP XOR

    ; Set up the registers for the call to MEMCMP
    ASET 12
    SPOP
    ASET 9
    SPOP
    ASET 8
    SPOP

    ASET 14
    BRnp STRCMP_RETURN  ; Return if the lengths are not equal



    OS_LOCALSYSCALL MEMCMP
    


    STRCMP_RETURN:
    ASET 8
    SPOP
    ASET 9
    SPOP
    ASET 10
    SPOP
    ASET 11
    SPOP

    ASET 14
    OS_SYSCALL_RET
