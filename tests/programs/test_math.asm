; asmsyntax=apricos
;
; libmath tests (run with MEMEXEC 4500).
;
; Output lines (bytes in hex):
;   MULT a b product overflow       one line per pair in MULT_CASES
;   FASTMULT a b product            one line per pair in FASTMULT_CASES
;   DIV a b quotient remainder      one line per pair in DIV_CASES
;   POW a b result overflow         one line per pair in POW_CASES
;   ATOB ok value                   for "123", "7", "255", "0", "1234" (too long)
;   HTOI high low                   for "1A2B", "F", "0", "FFFF"
;   RAND r1 r2 r3 r4 r5             after SET_RAND_SEED(1)
;   RAND r1 r2 r3                   after SET_RAND_SEED(0x5A)
;
; Each table is a list of (a, b) byte pairs ended by the pair (0xFF, 0xFF).
;
; Each test section sits in its own segment and calls the next one, so that
; its loop's local branches stay within a page. In every loop, $a1 is the
; table pointer and $a3/$a4 the operands (callee-saved, so they survive the
; calls); results are moved to $a5/$a6 before printing, because printing
; clobbers $a8-$a15. Non-zero overflow flags are printed as 01.
;

#segment 0x45
#name "test_math"

#include "apricotos.asm"
#include "math.asm"
#include "disp.asm"
#include "testlib.asm"
#include "testmacros.asm"

    ; ------------------------------------------------------------ MULT
    ASET 1
    LARl MULT_CASES
    MULT_LOOP:
        OS_CALLFUNC LOAD_PAIR
        ASET 8
        BRz MULT_DONE
        TM_LABEL T_MULT
        TM_PREG 3
        TM_PREG 4
        TM_MOVE 3 8
        TM_MOVE 4 9
        OS_CALLFUNC LIBMATH_MULT
        TM_MOVE 10 5
        TM_MOVE 11 6
        TM_PREG 5
        ASET 6
        BRz MULT_NO_OVERFLOW
        TM_SET 6 1
        MULT_NO_OVERFLOW:
        TM_PREG 6
        TM_NL
        JMP MULT_LOOP
    MULT_DONE:
    OS_CALLFUNC FASTMULT_TESTS
    OS_PROG_EXIT

T_MULT:     .stringz "MULT "
T_FASTMULT: .stringz "FASTMULT "
T_DIV:      .stringz "DIV "
T_POW:      .stringz "POW "


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

FASTMULT_TESTS:
    ASET 1
    LARl FASTMULT_CASES
    FASTMULT_LOOP:
        OS_CALLFUNC LOAD_PAIR
        ASET 8
        BRz FASTMULT_DONE
        TM_LABEL T_FASTMULT
        TM_PREG 3
        TM_PREG 4
        TM_MOVE 3 8
        TM_MOVE 4 9
        OS_CALLFUNC LIBMATH_FASTMULT
        TM_MOVE 10 5
        TM_PREG 5
        TM_NL
        JMP FASTMULT_LOOP
    FASTMULT_DONE:
    OS_CALLFUNC DIV_TESTS
    OS_FUNC_RETURN


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

DIV_TESTS:
    ASET 1
    LARl DIV_CASES
    DIV_LOOP:
        OS_CALLFUNC LOAD_PAIR
        ASET 8
        BRz DIV_DONE
        TM_LABEL T_DIV
        TM_PREG 3
        TM_PREG 4
        TM_MOVE 3 8
        TM_MOVE 4 9
        OS_CALLFUNC LIBMATH_DIV
        TM_MOVE 10 5
        TM_MOVE 11 6
        TM_PREG 5
        TM_PREG 6
        TM_NL
        JMP DIV_LOOP
    DIV_DONE:
    OS_CALLFUNC POW_TESTS
    OS_FUNC_RETURN


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

POW_TESTS:
    ASET 1
    LARl POW_CASES
    POW_LOOP:
        OS_CALLFUNC LOAD_PAIR
        ASET 8
        BRz POW_DONE
        TM_LABEL T_POW
        TM_PREG 3
        TM_PREG 4
        TM_MOVE 3 8
        TM_MOVE 4 9
        OS_CALLFUNC LIBMATH_POW
        TM_MOVE 10 5
        TM_MOVE 11 6
        TM_PREG 5
        ASET 6
        BRz POW_NO_OVERFLOW
        TM_SET 6 1
        POW_NO_OVERFLOW:
        TM_PREG 6
        TM_NL
        JMP POW_LOOP
    POW_DONE:
    OS_CALLFUNC CONVERSION_TESTS
    OS_FUNC_RETURN


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

CONVERSION_TESTS:
    ; ATOB
    ASET 1
    LARl ATOB_CASES
    ATOB_LOOP:
        LAh ATOB_CASES
        ASET 1
        STal
        ASET 8
        LD
        BRz ATOB_DONE
        TM_LABEL T_ATOB
        ASET 8
        LARh ATOB_CASES
        ASET 1
        SPUSH
        ASET 9
        SPOP
        OS_CALLFUNC LIBMATH_ATOB
        TM_MOVE 10 5
        TM_MOVE 11 6
        ASET 5
        BRz ATOB_FAILED
        TM_SET 5 1
        ATOB_FAILED:
        TM_PREG 5
        TM_PREG 6
        TM_NL
        ATOB_SKIP:     ; Skip to the byte after the string's NUL
            LAh ATOB_CASES
            ASET 1
            STal
            ADD 1
            ASET 8
            LD
            BRnp ATOB_SKIP
        JMP ATOB_LOOP
    ATOB_DONE:

    ; HTOI
    ASET 1
    LARl HTOI_CASES
    HTOI_LOOP:
        LAh HTOI_CASES
        ASET 1
        STal
        ASET 8
        LD
        BRz HTOI_DONE
        TM_LABEL T_HTOI
        ASET 8
        LARh HTOI_CASES
        ASET 1
        SPUSH
        ASET 9
        SPOP
        OS_CALLFUNC LIBMATH_HTOI
        TM_MOVE 10 5
        TM_MOVE 11 6
        TM_PREG 5
        TM_PREG 6
        TM_NL
        HTOI_SKIP:
            LAh HTOI_CASES
            ASET 1
            STal
            ADD 1
            ASET 8
            LD
            BRnp HTOI_SKIP
        JMP HTOI_LOOP
    HTOI_DONE:
    OS_CALLFUNC RAND_TESTS
    OS_FUNC_RETURN

T_ATOB: .stringz "ATOB "
T_HTOI: .stringz "HTOI "

; Strings, each NUL terminated, ended by an empty string
ATOB_CASES:
.stringz "123"
.stringz "7"
.stringz "255"
.stringz "0"
.stringz "1234"
.fill 0

HTOI_CASES:
.stringz "1A2B"
.stringz "F"
.stringz "0"
.stringz "FFFF"
.fill 0


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

RAND_TESTS:
    TM_SET 8 1
    OS_CALLFUNC LIBMATH_SET_RAND_SEED
    TM_LABEL T_RAND
    TM_SET 1 0xFB      ; -5
    RAND_LOOP_1:
        OS_CALLFUNC LIBMATH_RAND
        TM_PREG 10
        ASET 1
        ADD 1
        BRnp RAND_LOOP_1
    TM_NL

    TM_SET 8 0x5A
    OS_CALLFUNC LIBMATH_SET_RAND_SEED
    TM_LABEL T_RAND
    TM_SET 1 0xFD      ; -3
    RAND_LOOP_2:
        OS_CALLFUNC LIBMATH_RAND
        TM_PREG 10
        ASET 1
        ADD 1
        BRnp RAND_LOOP_2
    TM_NL
    OS_FUNC_RETURN

T_RAND: .stringz "RAND "


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

; LOAD_PAIR and the operand tables share this segment (LOAD_PAIR only
; sets the low byte of the table address).
;
; Load the next pair from the table at $a1 (in this segment) into $a3 and
; $a4, and advance $a1. Returns $a8 = 0 at the end of the table.
;
LOAD_PAIR:
    LAh MULT_CASES
    ASET 1
    STal
    ASET 3
    LD
    ASET 1
    ADD 1
    STal
    ASET 4
    LD
    ASET 1
    ADD 1
    TM_MOVE 3 8
    ASET 4
    SPUSH
    ASET 8
    SPOP AND
    ADD 1              ; Zero only for the (0xFF, 0xFF) end marker
    OS_FUNC_RETURN



MULT_CASES:
.fill 7
.fill 6
.fill 1
.fill 200
.fill 2
.fill 200
.fill 16
.fill 16
.fill 0
.fill 255
.fill 255
.fill 1
.fill 15
.fill 17
.fill 0xFF
.fill 0xFF

FASTMULT_CASES:
.fill 7
.fill 6
.fill 12
.fill 10
.fill 85
.fill 3
.fill 0
.fill 9
.fill 0xFF
.fill 0xFF

DIV_CASES:
.fill 100
.fill 7
.fill 200
.fill 7
.fill 128
.fill 1
.fill 0
.fill 5
.fill 127
.fill 127
.fill 250
.fill 3
.fill 9
.fill 10
.fill 0xFF
.fill 0xFF

POW_CASES:
.fill 2
.fill 7
.fill 3
.fill 6
.fill 5
.fill 0
.fill 129
.fill 2
.fill 2
.fill 8
.fill 0xFF
.fill 0xFF
