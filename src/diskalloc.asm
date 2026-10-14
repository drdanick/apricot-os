; asmsyntax=apricos
; ===================================
; ==                               ==
; ==     ApricotOS Disk Storage    ==
; ==           Allocator           ==
; ==                               ==
; ==          Revision 2           ==
; ==                               ==
; ==  (C) 2017 Nick Stones-Havas   ==
; ==                               ==
; ==                               ==
; ==  Provides a collection of     ==
; ==  storage allocation routines. ==
; ==                               ==
; ===================================
;
; All routines operate on the in-memory copy of the space bitmap
; (FSMEM_VOL_BITMAP). Nothing is written to disk until FLUSH_BITMAP
; is called.
;
; Bitmap layout: sector (track, sector) is block b = track*64 + sector,
; stored in byte b/8 (= track*8 + sector/8), bit b%8 (LSB first).
; A set bit means the sector is allocated.
;

#name "diskalloc"
#segment 7

#include "apricotosint.asm"
#include "fsmem.asm"
#include "diskio.asm"
#include "portout.asm"


;
; Locate the bitmap bit for a sector.
; $a8 - The track number
; $a9 - The sector number
;
; Returns:
; $a8  - The offset of the bitmap byte within FSMEM_VOL_BITMAP
; $a10 - A mask with only the sector's bit set
;
; Volatile registers:
; $a8, $a9, $a10
;
BITPOS:
    ASET 9
    SPUSH
    SHFr 3
    SPUSH
    ASET 8
    SHFl 3
    SPOP ADD       ; $a8 = track*8 + sector/8

    ASET 10        ; $a10 = 1
    AND 0
    ADD 1
    ASET 9
    SPOP
    AND 7          ; $a9 = sector % 8 (number of shifts left)

    BITPOS_LP:
        BRz BITPOS_END
        ASET 10
        SHFl 1
        ASET 9
        NOT        ; $a9 -= 1
        ADD 1
        NOT
        JMP BITPOS_LP
    BITPOS_END:

    ASET 9
    OS_SYSCALL_RET


;
; Check if a disk sector is free or not.
; $a8 - The track number of the sector to check
; $a9 - The sector number to check
;
; Returns:
; $a8 - Zero if the sector is free, non-zero otherwise
;
; Volatile registers:
; $a8, $a9, $a10, $a15
;
CHECK_SECTOR:
    ASET 15
    OS_LOCALSYSCALL BITPOS

    LAh FSMEM_VOL_BITMAP
    ASET 8
    STal
    LD             ; $a8 = bitmap byte
    ASET 10
    SPUSH
    ASET 8
    SPOP AND       ; $a8 = bitmap byte & mask

    ASET 9
    OS_SYSCALL_RET


;
; Find and allocate the first available sector (first fit,
; tracks 1-31). Only the in-memory bitmap is changed.
;
; Returns:
; $a8  - Status: 0 if successful, 6 (disk full) otherwise
; $a9  - The track number of the allocated sector
; $a10 - The sector number of the allocated sector
;
; Volatile registers:
; $a8 - $a13
;
AUTO_ALLOCATE_SECTOR:
    LAh FSMEM_VOL_BITMAP
    ASET 9
    LARl 8         ; Skip track 0 (bytes 0-7)

    ; Find the first bitmap byte with a clear bit. The offset ($a9) runs
    ; 8..255 (tracks 1-31) and the loop ends when it wraps to 0.
    AA_SCAN:
        STal
        ASET 10
        LD
        NOT        ; Zero if all 8 sectors are allocated
        BRnp AA_FOUND
        ASET 9
        ADD 1
        BRnp AA_SCAN

    ; Every byte is 0xFF: the disk is full
    ASET 8
    LARl 6
    ASET 9
    OS_SYSCALL_RET

    AA_FOUND:
    ; $a9 = byte offset, $a10 = inverted byte (1 = free), $mr -> bitmap byte
    ASET 11        ; $a11 = bit number
    AND 0
    ASET 12        ; $a12 = bit mask
    AND 0
    ADD 1

    ; Shift the inverted byte right until bit 0 is set, counting the shifts
    ; in $a11 and moving the mask left in step with it
    AA_BIT:
        ASET 10
        SPUSH
        ASET 13
        SPOP
        AND 1
        BRnp AA_BIT_FOUND
        ASET 10
        SHFr 1
        ASET 12
        SHFl 1
        ASET 11
        ADD 1
        JMP AA_BIT
    AA_BIT_FOUND:

    ; Mark the sector as allocated ($mr still points at the byte)
    ASET 13
    LD
    ASET 12
    SPUSH
    ASET 13
    SPOP OR
    ST

    ; sector = (offset % 8) * 8 + bit, track = offset / 8
    ASET 9
    SPUSH
    AND 7
    SHFl 3
    SPUSH
    ASET 11
    SPOP ADD       ; $a11 = sector
    ASET 9
    SPOP
    SHFr 3         ; $a9 = track
    ASET 11
    SPUSH
    ASET 10
    SPOP           ; $a10 = sector

    ASET 8
    AND 0
    ASET 11
    OS_SYSCALL_RET


;
; Free a given sector. Sectors on track 0 are never freed.
; Only the in-memory bitmap is changed.
;
; $a8 - The track number of the sector to free
; $a9 - The sector number to free
;
; Volatile registers:
; $a8 - $a11, $a15
;
FREE_SECTOR:
    ASET 8
    BRz FREE_SECTOR_RET

    ASET 15
    OS_LOCALSYSCALL BITPOS

    LAh FSMEM_VOL_BITMAP
    ASET 8
    STal
    ASET 10
    NOT            ; $a10 = ~mask
    ASET 11
    LD
    ASET 10
    SPUSH
    ASET 11
    SPOP AND
    ST

    FREE_SECTOR_RET:
    ASET 11
    OS_SYSCALL_RET


;
; Write the in-memory space bitmap back to disk (track 0, sector 63).
;
; Volatile registers:
; $a8 - $a11
;
FLUSH_BITMAP:
    ASET 8
    DISKIO_TRACKSEL 0
    LARh FSMEM_VOL_BITMAP
    ASET 9
    LARl 63
    ASET 10
    OS_SYSCALL DISKIO_COPYTODSK

    ASET 10
    OS_SYSCALL_RET
