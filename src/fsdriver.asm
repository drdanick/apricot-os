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
#segment 16

#include "apricotosint.asm"
#include "fsmem.asm"
#include "diskio.asm"

.nearptr MOUNT_DISK


;
; Mount a filesystem on the currently loaded disk
;
; Volatile registers:
; $a8
;
MOUNT_DISK:
    ASET 8
    DISKIO_TRACKSEL 0

    ; Load the volume information sector into memory (sector 62)
    LARl 62
    ASET 9
    LARh FSMEM_VOL_INFO
    ASET 10
    MEOW:
    OS_SYSCALL DISKIO_COPYFROMDSK

    ; Load the space bitmap sector into memory (sector 63)
    ASET 8
    LARl 63
    ASET 9
    LARh FSMEM_VOL_BITMAP
    ASET 10
    OS_SYSCALL DISKIO_COPYFROMDSK

    OS_SYSCALL_RET
