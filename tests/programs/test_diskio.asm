; asmsyntax=apricos
;
; diskio tests (run with MEMEXEC 5500) on disk 0. Writes to sectors of
; tracks 28-31 that the test disk doesn't use. Uses scratch RAM 0x7000-0x73FF.
;
; Output lines (bytes in hex):
;   COPY first and last byte of a sector written with COPYTODSK (28/40)
;        and read back with COPYFROMDSK
;   BULK first byte of each of the 4 sectors 30/8-30/11 (prepared by the
;        Python test) read with COPYBULKFROMDSK
; The Python test also checks the disk image afterwards: the COPYBULKTODSK
; of 4 sectors to 30/2-30/5, and one of 3 sectors from 29/14, which crosses
; sector 15.
;

#segment 0x55
#name "test_diskio"

#include "apricotos.asm"
#include "memutil.asm"
#include "diskio.asm"
#include "portout.asm"
#include "disp.asm"
#include "testlib.asm"
#include "testmacros.asm"

#macro FILL segment value {
    TM_SET 8 segment
    TM_SET 9 value
    OS_CALLFUNC MEMUTIL_SEGSET
}

    ; COPYTODSK / COPYFROMDSK on track 28, sector 40
    FILL 0x70 0xC3
    ASET 8
    DISKIO_TRACKSEL 28
    TM_SET 8 0x70
    TM_SET 9 40
    OS_CALLFUNC DISKIO_COPYTODSK
    FILL 0x71 0x00
    ASET 8
    DISKIO_TRACKSEL 28
    TM_SET 8 40
    TM_SET 9 0x71
    OS_CALLFUNC DISKIO_COPYFROMDSK
    TM_LABEL T_COPY
    TM_PMEM 0x71 0x00
    TM_PMEM 0x71 0xFF
    TM_NL

    ; COPYBULKTODSK: 4 sectors from 0x70-0x73 to track 30, sectors 2-5
    FILL 0x70 0x11
    FILL 0x71 0x22
    FILL 0x72 0x33
    FILL 0x73 0x44
    TM_SET 8 0x70
    TM_SET 9 2
    TM_SET 10 30
    TM_SET 11 4
    OS_CALLFUNC DISKIO_COPYBULKTODSK

    ; COPYBULKFROMDSK: read 30/8-30/11 into 0x70-0x73
    FILL 0x70 0x00
    FILL 0x71 0x00
    FILL 0x72 0x00
    FILL 0x73 0x00
    TM_SET 8 8
    TM_SET 9 0x70
    TM_SET 10 30
    TM_SET 11 4
    OS_CALLFUNC DISKIO_COPYBULKFROMDSK
    TM_LABEL T_BULK
    TM_PMEM 0x70 0x00
    TM_PMEM 0x71 0x00
    TM_PMEM 0x72 0x00
    TM_PMEM 0x73 0x00
    TM_NL

    ; COPYBULKTODSK of 3 sectors starting at 29/14 (crosses sector 15)
    FILL 0x70 0x77
    FILL 0x71 0x88
    FILL 0x72 0x99
    TM_SET 8 0x70
    TM_SET 9 14
    TM_SET 10 29
    TM_SET 11 3
    OS_CALLFUNC DISKIO_COPYBULKTODSK
    TM_LABEL T_DONE
    TM_NL
    OS_PROG_EXIT

T_COPY: .stringz "COPY "
T_BULK: .stringz "BULK "
T_DONE: .stringz "DONE"
