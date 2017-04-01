; asmsyntax=apricos
; ===================================
; ==                               ==
; ==  ApricotOS Filesystem Driver  ==
; ==                               ==
; ==          Revision 1           ==
; ==                               ==
; ==  (C) 2017  Nick Stones-Havas  ==
; ==                               ==
; ==  Provides a driver for the    ==
; ==  Apricot Filesystem.          ==
; ==                               ==
; ===================================
;

#name "fs"
#segment 17

#include "apricotosint.asm"
#include "fsmem.asm"
#include "diskio.asm"

.nearptr MOUNT_DISK


;
; Mount a filesystem on the currently loaded disk
;
; Volatile registers:
; $a8-$a15
;
; Returns:
; $a8 - Non-zero if the disk was mounted successfully, zero otherwise.
;
MOUNT_DISK:
    ASET 8
    DISKIO_TRACKSEL 0

    ; Load the volume information sector into memory (sector 62)
    LARl 62
    ASET 9
    LARh FSMEM_VOL_INFO
    ASET 10
    OS_SYSCALL DISKIO_COPYFROMDSK

    ; Load the space bitmap sector into memory (sector 63)
    ASET 8
    LARl 63
    ASET 9
    LARh FSMEM_VOL_BITMAP
    ASET 10
    OS_SYSCALL DISKIO_COPYFROMDSK

    ; Validate the disk by checking that the first 4 bytes of
    ; this sector are 0xC0, 0x30, 0x0C, and 0x03.
    ; Xoring them together will produce 0xFF.

    ASET 8 ; Set the return value to be initially non-zero
    OR 1

    LAh FSMEM_VOL_INFO
    LAl 0x00
    ASET 9
    LD
    SPUSH
    LDal
    ADD 1
    STal
    LD
    SPUSH
    LDal
    ADD 1
    STal
    LD
    SPUSH
    LDal
    ADD 1
    STal
    LD
    SPOP XOR
    SPOP XOR
    SPOP XOR
    ADD 1 ; Adding 1 will make it zero if the result was 0xFF (The only valid result)
    BRz MOUNT_DISK_END

    ; Disk was not valid, so set the return value to be zero
    ASET 8
    AND 0

    MOUNT_DISK_END:
    ASET 10
    OS_SYSCALL_RET
