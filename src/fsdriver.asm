; asmsyntax=apricos
; ===================================
; ==                               ==
; ==  ApricotOS Filesystem Driver  ==
; ==                               ==
; ==          Revision 2           ==
; ==                               ==
; ==  (C) 2017  Nick Stones-Havas  ==
; ==                               ==
; ==  Provides a driver for the    ==
; ==  Apricot Filesystem.          ==
; ==                               ==
; ===================================
;
; Core of the filesystem driver: mounting, the no-filesystem notice, and
; track/sector I/O wrappers used by every other fs* unit.
;
; Segment 17: MOUNT_DISK, INIT, NOTICE, PATH_RESET
; Segment 18: READ_SECTOR, WRITE_SECTOR
;
; Filesystem routines return a status code in $a8:
;  0 - OK
;  1 - No filesystem          7 - File too big
;  2 - Not found              8 - Not a directory
;  3 - Already exists         9 - Not a file
;  4 - Bad name              10 - Directory not empty
;  5 - Directory full        11 - Path too deep
;  6 - Disk full             12 - Missing argument
;                            13 - No such disk
;

#name "fs"
#segment 17

#include "apricotosint.asm"
#include "fsmem.asm"
#include "fsbuf.asm"
#include "diskio.asm"
#include "diskalloc.asm"
#include "memutil.asm"
#include "disp.asm"
#include "portout.asm"


;
; Mount the filesystem on the currently selected disk.
; The disk is valid if its signature is correct, track 0 is marked
; as allocated (bitmap byte 0 is 0xFF) and the root directory
; (track 1, sector 0) is allocated. Sets FSBUF_MOUNTED, and
; FSBUF_VOLSTATE to 0 (mounted), 1 (no signature) or 2 (not formatted).
;
; Returns:
; $a8 - Non-zero if the disk was mounted successfully, zero otherwise.
;
; Volatile registers:
; $a8-$a15
;
MOUNT_DISK:
    ASET 8
    DISKIO_TRACKSEL 0

    ; Load the volume information sector into memory (sector 63)
    LARl 63
    ASET 9
    LARh FSMEM_VOL_INFO
    ASET 10
    OS_SYSCALL DISKIO_COPYFROMDSK

    ; Load the space bitmap sector into memory (sector 62)
    ASET 8
    LARl 62
    ASET 9
    LARh FSMEM_VOL_BITMAP
    ASET 10
    OS_SYSCALL DISKIO_COPYFROMDSK

    ASET 10        ; $a10 = volume state 1 (no signature) if the check below fails
    AND 0
    ADD 1

    ; Check that the first 4 bytes of this sector are exactly 0xC0, 0x30,
    ; 0x0C and 0x03. Each byte is the previous one shifted right by 2, and
    ; one more shift gives 0, so $a11 holds both the expected byte and the
    ; loop counter (as in the boot loader).
    LAh FSMEM_VOL_INFO
    LAl 0x00
    ASET 11
    LARl 0xC0      ; Expected first byte
    MOUNT_DISK_SIG_LP:
        SPUSH      ; $a11 is selected here on every pass
        ASET 9
        LD         ; Load the next signature byte
        SPOP XOR   ; Zero only if it matches
        BRnp MOUNT_DISK_FAIL
        LDal       ; $mr += 1
        ADD 1
        STal
        ASET 11
        SHFr 2     ; 0xC0 -> 0x30 -> 0x0C -> 0x03 -> 0
        BRnp MOUNT_DISK_SIG_LP

    ASET 10        ; $a10 = volume state 2 (not formatted) if a check below fails
    ADD 1

    ; Track 0 must be allocated
    LAh FSMEM_VOL_BITMAP
    LAl 0
    ASET 9
    LD
    NOT
    BRnp MOUNT_DISK_FAIL

    ; The root directory (block 64: byte 8, bit 0) must be allocated
    LAl 8
    LD
    AND 1
    BRz MOUNT_DISK_FAIL

    ASET 10        ; Volume state 0: mounted
    AND 0
    ASET 8
    AND 0
    ADD 1
    JMP MOUNT_DISK_END

    MOUNT_DISK_FAIL:
    ASET 8
    AND 0

    ; Record the result: FSBUF_MOUNTED = $a8, FSBUF_VOLSTATE = $a10
    MOUNT_DISK_END:
    LAh FSBUF_MOUNTED
    LAl FSBUF_MOUNTED
    ST
    LAl FSBUF_VOLSTATE
    ASET 10
    ST
    ASET 11
    OS_SYSCALL_RET


;
; Initialise the filesystem driver: mount disk 0 and reset the
; working directory to the root.
;
; Volatile registers:
; $a8-$a15
;
INIT:
    ASET 8
    OS_LOCALSYSCALL MOUNT_DISK
    ASET 8
    OS_LOCALSYSCALL PATH_RESET
    ASET 8
    OS_SYSCALL_RET


;
; Print a notice if no filesystem is mounted.
;
; Volatile registers:
; $a8-$a10
;
NOTICE:
    LAh FSBUF_MOUNTED
    LAl FSBUF_MOUNTED
    ASET 8
    LD
    BRnp NOTICE_END
    LARh NO_FS_MSG
    ASET 9
    LARl NO_FS_MSG
    ASET 10
    OS_SYSCALL LIBDISP_PUTSTR
    NOTICE_END:
    ASET 8
    OS_SYSCALL_RET


;
; Reset the working directory to the root, by truncating the path
; stack to its root entry (FSBUF_PATH_DEPTH = 1).
;
; Volatile registers:
; $a8
;
PATH_RESET:
    LAh FSBUF_PATH_DEPTH
    LAl FSBUF_PATH_DEPTH
    ASET 8
    AND 0
    ADD 1
    ST
    OS_SYSCALL_RET

NO_FS_MSG: .stringz "NO FILESYSTEM - TYPE FORMAT\n"


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

;
; Read a disk sector into a memory segment, on the selected disk.
; $a8  - The track number
; $a9  - The sector number
; $a10 - The destination memory segment
;
; Volatile registers:
; $a8-$a11
;
READ_SECTOR:
    ASET 8
    PORTOUT_DISK_TRACKSEL
    ; Shuffle the arguments into DISKIO_COPYFROMDSK's order
    ASET 10
    SPUSH
    ASET 9
    SPUSH
    ASET 8
    SPOP           ; $a8 = sector
    ASET 9
    SPOP           ; $a9 = destination segment
    ASET 10
    OS_SYSCALL DISKIO_COPYFROMDSK
    ASET 10
    OS_SYSCALL_RET


;
; Write a memory segment to a disk sector.
; Writing to track 0 is a fault (only DISKALLOC_FLUSH_BITMAP and
; FSFORMAT_FLUSH_VOLINFO write there).
; $a8  - The track number
; $a9  - The sector number
; $a10 - The source memory segment
;
; Volatile registers:
; $a8-$a11
;
WRITE_SECTOR:
    ASET 8
    BRnp WRITE_SECTOR_OK
    OS_SYSJUMP DISKIO_TRACKNUM_ERROR
    WRITE_SECTOR_OK:
    PORTOUT_DISK_TRACKSEL
    ; DISKIO_COPYTODSK takes (segment, sector), so only $a8 changes
    ASET 10
    SPUSH
    ASET 8
    SPOP           ; $a8 = source segment, $a9 = sector
    ASET 10
    OS_SYSCALL DISKIO_COPYTODSK
    ASET 10
    OS_SYSCALL_RET
