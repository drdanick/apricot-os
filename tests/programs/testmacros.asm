; asmsyntax=apricos
;
; Macros for the library test programs (header only: no code, no segment).
; A program that uses them must also #include "apricotos.asm", "disp.asm"
; and "testlib.asm" (macros are expanded in the caller's context).
;
; Use them with the tm_ prefix, e.g. "TM_SET 8 0x2A".
;

#name "tm"

#include "apricotos.asm"
#include "disp.asm"
#include "testlib.asm"

; Print a NUL-terminated string label (e.g. a test name).
#macro LABEL text {
    ASET 8
    LARh text
    ASET 9
    LARl text
    OS_CALLFUNC LIBDISP_PUTSTR
}

; Print accumulator r in hex.
#macro PREG r {
    ASET r
    SPUSH
    ASET 8
    SPOP
    OS_CALLFUNC TESTLIB_HEX
}

; Print the byte at address hi:lo in hex.
#macro PMEM hi lo {
    LAh hi
    LAl lo
    ASET 8
    LD
    OS_CALLFUNC TESTLIB_HEX
}

; End a result line.
#macro NL {
    OS_CALLFUNC TESTLIB_NEWLINE
}

; Copy accumulator src into dst.
#macro MOVE src dst {
    ASET src
    SPUSH
    ASET dst
    SPOP
}

; Load a constant into accumulator r.
#macro SET r value {
    ASET r
    LAR value
}

; Store a constant at address hi:lo.
#macro POKE hi lo value {
    LAh hi
    LAl lo
    ASET 15
    LAR value
    ST
}

; Store accumulator r at address hi:lo.
#macro STORE r hi lo {
    LAh hi
    LAl lo
    ASET r
    ST
}
