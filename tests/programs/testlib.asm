; asmsyntax=apricos
;
; Support routines for the library test programs.
;
; Loaded at 0x4000 alongside the test programs (see tests/test_library.py).
; Test programs print their results as lines of the form
;     NAME XX XX XX
; where each XX is a byte in hex, and the Python tests parse those lines.
;

#segment 0x40
#name "testlib"

#include "apricotos.asm"


;
; Print $a8 as two hex digits followed by a space.
;
; Volatile registers:
; $a8-$a10, $a15
;
HEX:
    ASET 8
    SPUSH
    SHFr 4
    OS_CALLFUNC_LOCAL NIBBLE
    ASET 8
    SPOP
    AND 15
    OS_CALLFUNC_LOCAL NIBBLE
    ASET 8
    LAR 0x20
    PRTout 7
    OS_FUNC_RETURN


;
; Print a newline.
;
; Volatile registers:
; $a8, $a15
;
NEWLINE:
    ASET 8
    LAR 0x0A
    PRTout 7
    OS_FUNC_RETURN


;
; Print the hex digit for $a8 (0-15).
;
; Volatile registers:
; $a8-$a10, $a15
;
NIBBLE:
    ASET 8
    SPUSH
    ASET 9
    LAR 0xF6           ; -10
    SPOP ADD
    BRn NIBBLE_DIGIT
    SPUSH              ; $a9 = value - 10: print 'A' + $a9
    ASET 10
    LAR 0x41
    SPOP ADD
    PRTout 7
    JMP NIBBLE_RET
    NIBBLE_DIGIT:
    ASET 8
    SPUSH
    ASET 10
    LAR 0x30
    SPOP ADD
    PRTout 7
    NIBBLE_RET:
    OS_FUNC_RETURN
