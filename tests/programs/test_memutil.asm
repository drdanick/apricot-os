; asmsyntax=apricos
;
; memutil tests (run with MEMEXEC 4100). Uses scratch RAM at 0x7000-0x73FF.
;
; Output lines (bytes in hex):
;   SEGSET  first and last byte of segment 0x70 after SEGSET(0x70, 0xAB)
;   SEGCPY  first and last byte of segment 0x71 after SEGCPY(0x70 -> 0x71)
;   MEMSET  bytes 0x70EF 0x70F0 0x710F 0x7110 after MEMSET(0x70F0, 32, 0x5A)
;   MEMCPY  the 6 bytes at 0x71FE after copying "HELLO" (and its NUL) there
;   STRLEN  STRLEN of that copy (it crosses a page)
;   MEMCMP  MEMCMP(HELLO, copy, 5), then MEMCMP(HELLP, copy, 5)
;   STRCMP  STRCMP(copy, HELLO), (copy, HELL), (copy, HELLP); 0 = different
;

#segment 0x41
#name "test_memutil"

#include "apricotos.asm"
#include "memutil.asm"
#include "disp.asm"
#include "testlib.asm"
#include "testmacros.asm"

    ; SEGSET
    TM_SET 8 0x70
    TM_SET 9 0xAB
    OS_CALLFUNC MEMUTIL_SEGSET
    TM_LABEL T_SEGSET
    TM_PMEM 0x70 0x00
    TM_PMEM 0x70 0xFF
    TM_NL

    ; SEGCPY
    TM_SET 8 0x70
    TM_SET 9 0x71
    OS_CALLFUNC MEMUTIL_SEGCPY
    TM_LABEL T_SEGCPY
    TM_PMEM 0x71 0x00
    TM_PMEM 0x71 0xFF
    TM_NL

    ; MEMSET across the 0x70/0x71 page boundary
    TM_SET 8 0x70
    TM_SET 9 0xF0
    TM_SET 10 32
    TM_SET 11 0x5A
    OS_CALLFUNC MEMUTIL_MEMSET
    TM_LABEL T_MEMSET
    TM_PMEM 0x70 0xEF
    TM_PMEM 0x70 0xF0
    TM_PMEM 0x71 0x0F
    TM_PMEM 0x71 0x10
    TM_NL

    ; MEMCPY "HELLO\0" to 0x71FE, across the 0x71/0x72 page boundary
    ASET 8
    LARh S_HELLO
    ASET 9
    LARl S_HELLO
    TM_SET 10 0x71
    TM_SET 11 0xFE
    TM_SET 12 6
    OS_CALLFUNC MEMUTIL_MEMCPY
    TM_LABEL T_MEMCPY
    TM_PMEM 0x71 0xFE
    TM_PMEM 0x71 0xFF
    TM_PMEM 0x72 0x00
    TM_PMEM 0x72 0x01
    TM_PMEM 0x72 0x02
    TM_PMEM 0x72 0x03
    TM_NL

    ; STRLEN of the copy
    TM_SET 8 0x71
    TM_SET 9 0xFE
    OS_CALLFUNC MEMUTIL_STRLEN
    TM_MOVE 13 0
    TM_LABEL T_STRLEN
    TM_PREG 0
    TM_NL

    ; MEMCMP
    ASET 8
    LARh S_HELLO
    ASET 9
    LARl S_HELLO
    TM_SET 10 0x71
    TM_SET 11 0xFE
    TM_SET 12 5
    OS_CALLFUNC MEMUTIL_MEMCMP
    TM_MOVE 13 0
    ASET 8
    LARh S_HELLP
    ASET 9
    LARl S_HELLP
    TM_SET 10 0x71
    TM_SET 11 0xFE
    TM_SET 12 5
    OS_CALLFUNC MEMUTIL_MEMCMP
    TM_MOVE 13 1
    TM_LABEL T_MEMCMP
    TM_PREG 0
    TM_PREG 1
    TM_NL

    ; STRCMP
    TM_SET 8 0x71
    TM_SET 9 0xFE
    ASET 10
    LARh S_HELLO
    ASET 11
    LARl S_HELLO
    OS_CALLFUNC MEMUTIL_STRCMP
    TM_MOVE 13 0
    TM_SET 8 0x71
    TM_SET 9 0xFE
    ASET 10
    LARh S_HELL
    ASET 11
    LARl S_HELL
    OS_CALLFUNC MEMUTIL_STRCMP
    TM_MOVE 13 1
    TM_SET 8 0x71
    TM_SET 9 0xFE
    ASET 10
    LARh S_HELLP
    ASET 11
    LARl S_HELLP
    OS_CALLFUNC MEMUTIL_STRCMP
    TM_MOVE 13 2
    TM_LABEL T_STRCMP
    TM_PREG 0
    TM_PREG 1
    TM_PREG 2
    TM_NL

    OS_PROG_EXIT

T_SEGSET: .stringz "SEGSET "
T_SEGCPY: .stringz "SEGCPY "
T_MEMSET: .stringz "MEMSET "
T_MEMCPY: .stringz "MEMCPY "
T_STRLEN: .stringz "STRLEN "
T_MEMCMP: .stringz "MEMCMP "
T_STRCMP: .stringz "STRCMP "
S_HELLO:  .stringz "HELLO"
S_HELLP:  .stringz "HELLP"
S_HELL:   .stringz "HELL"
