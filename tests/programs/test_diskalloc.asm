; asmsyntax=apricos
;
; diskalloc tests (run with MEMEXEC 5800). The test disk has exactly three
; free sectors (1/7, 25/2 and 31/63) in the in-memory bitmap when this runs.
;
; Output lines (bytes in hex):
;   ALLOC status track sector        four times: three successes, then disk full
;   CHECK a b                        CHECK_SECTOR(25/2) after freeing it, CHECK_SECTOR(1/0)
;   ALLOC status track sector        allocating again reuses 25/2
; The bitmap is then flushed to disk, and the Python test checks it.
;

#segment 0x58
#name "test_diskalloc"

#include "apricotos.asm"
#include "diskalloc.asm"
#include "disp.asm"
#include "testlib.asm"
#include "testmacros.asm"

    OS_CALLFUNC ALLOC
    OS_CALLFUNC ALLOC
    OS_CALLFUNC ALLOC
    OS_CALLFUNC ALLOC

    TM_SET 8 25
    TM_SET 9 2
    OS_CALLFUNC DISKALLOC_FREE_SECTOR
    TM_SET 8 25
    TM_SET 9 2
    OS_CALLFUNC DISKALLOC_CHECK_SECTOR
    TM_MOVE 8 0
    TM_SET 8 1
    TM_SET 9 0
    OS_CALLFUNC DISKALLOC_CHECK_SECTOR
    TM_MOVE 8 1
    TM_LABEL T_CHECK
    TM_PREG 0
    TM_PREG 1
    TM_NL

    OS_CALLFUNC ALLOC
    OS_CALLFUNC DISKALLOC_FLUSH_BITMAP
    OS_PROG_EXIT

; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

; Allocate a sector and print "ALLOC status track sector".
ALLOC:
    OS_CALLFUNC DISKALLOC_AUTO_ALLOCATE_SECTOR
    TM_MOVE 8 0
    TM_MOVE 9 1
    TM_MOVE 10 2
    TM_LABEL T_ALLOC
    TM_PREG 0
    ASET 0
    BRnp ALLOC_FAILED      ; Track and sector are undefined when it fails
    TM_PREG 1
    TM_PREG 2
    ALLOC_FAILED:
    TM_NL
    OS_FUNC_RETURN

T_ALLOC: .stringz "ALLOC "
T_CHECK: .stringz "CHECK "
