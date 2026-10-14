; asmsyntax=apricos
;
; Fault test (run with MEMEXEC 5B00): DISKIO_COPYFROMDSK with sector 64.
; Expected: the fault handler prints "INVALID DISK IO: BAD SEGMENT #" and
; halts the machine.
;

#segment 0x5B
#name "fault_bad_sector"

#include "apricotos.asm"
#include "diskio.asm"

    ASET 8
    LAR 64
    ASET 9
    LAR 0x70
    OS_CALLFUNC DISKIO_COPYFROMDSK
    OS_PROG_EXIT
