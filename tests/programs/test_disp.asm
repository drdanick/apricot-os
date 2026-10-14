; asmsyntax=apricos
;
; libdisp tests (run with MEMEXEC 4D00). Uses scratch RAM at 0x70F8.
;
; Output lines:
;   PUTNUM XX <decimal>          LIBDISP_PUTNUM of each byte in PUTNUM_CASES
;   PUTNUM16 XX XX <decimal>     LIBDISP_PUTNUM16 of each pair in PUTNUM16_CASES
;   PUTSTR <text>                a string copied to 0x70FC, crossing a page
;

#segment 0x4D
#name "test_disp"

#include "apricotos.asm"
#include "memutil.asm"
#include "disp.asm"
#include "testlib.asm"
#include "testmacros.asm"

    ; PUTNUM: print every case, including the final 0 that ends the list.
    ; $a1 = case pointer (low byte), $a3 = case. Both are callee-saved, so
    ; they survive the calls.
    ASET 1
    LARl PUTNUM_CASES
    PUTNUM_LOOP:
        LAh PUTNUM_CASES
        ASET 1
        STal
        ASET 3
        LD
        ASET 1
        ADD 1
        TM_LABEL T_PUTNUM
        TM_PREG 3
        TM_MOVE 3 8
        OS_CALLFUNC LIBDISP_PUTNUM
        TM_NL
        ASET 3
        BRnp PUTNUM_LOOP      ; The last case is 0

    OS_CALLFUNC PUTNUM16_TESTS
    OS_PROG_EXIT

T_PUTNUM:   .stringz "PUTNUM "
T_PUTNUM16: .stringz "PUTNUM16 "
T_PUTSTR:   .stringz "PUTSTR "
S_TEXT:     .stringz "ABCDEFGH"

PUTNUM_CASES:
.fill 7
.fill 42
.fill 99
.fill 100
.fill 105
.fill 200
.fill 255
.fill 0

; (high, low) pairs; the last case is (0, 0)
PUTNUM16_CASES:
.fill 0x00
.fill 0x09
.fill 0x00
.fill 0x0A
.fill 0x00
.fill 0x63
.fill 0x00
.fill 0x64
.fill 0x03
.fill 0xE8
.fill 0x03
.fill 0xEC
.fill 0x07
.fill 0xC0
.fill 0x27
.fill 0x10
.fill 0x7F
.fill 0x00
.fill 0xFF
.fill 0xFF
.fill 0x00
.fill 0x00


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

; PUTNUM16: as PUTNUM, with $a3:$a4 = the case. The list ends with (0, 0).
PUTNUM16_TESTS:
    ASET 1
    LARl PUTNUM16_CASES
    PUTNUM16_LOOP:
        LAh PUTNUM16_CASES
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
        TM_LABEL T_PUTNUM16
        TM_PREG 3
        TM_PREG 4
        TM_MOVE 3 8
        TM_MOVE 4 9
        OS_CALLFUNC LIBDISP_PUTNUM16
        TM_NL
        ASET 3
        BRnp PUTNUM16_LOOP
        ASET 4
        BRnp PUTNUM16_LOOP

    ; PUTSTR of a string that crosses the 0x70/0x71 page boundary
    ASET 8
    LARh S_TEXT
    ASET 9
    LARl S_TEXT
    TM_SET 10 0x70
    TM_SET 11 0xFC
    TM_SET 12 9
    OS_CALLFUNC MEMUTIL_MEMCPY
    TM_LABEL T_PUTSTR
    TM_SET 8 0x70
    TM_SET 9 0xFC
    OS_CALLFUNC LIBDISP_PUTSTR
    TM_NL
    OS_FUNC_RETURN
