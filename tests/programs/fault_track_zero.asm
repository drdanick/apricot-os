; asmsyntax=apricos
;
; Fault test (run with MEMEXEC 5C00): FS_WRITE_SECTOR to track 0, which only
; the bitmap and volume-information writers may touch.
; Expected: the fault handler prints "INVALID DISK IO: BAD TRACK #" and
; halts the machine, without writing anything.
;

#segment 0x5C
#name "fault_track_zero"

#include "apricotos.asm"
#include "fsdriver.asm"

    ASET 8
    LAR 0
    ASET 9
    LAR 5
    ASET 10
    LAR 0x70
    OS_CALLFUNC FS_WRITE_SECTOR
    OS_PROG_EXIT
