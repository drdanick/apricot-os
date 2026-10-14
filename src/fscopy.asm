; asmsyntax=apricos
; ===================================
; ==                               ==
; ==  ApricotOS Filesystem         ==
; ==  copy routine                 ==
; ==                               ==
; ===================================
;
; Segment 42: COPY (CP)
; Segment 43: CP_BODY
; Segment 44: CP_NEWMETA, CP_FINISH, CP_ADD_ENTRY, CP_ROLLBACK
;
; Buffers: FSBUF_METABUF2 holds the source's metadata, FSBUF_METABUF the
; new file's, and FSBUF_DATABUF one block at a time.
;

#name "fscopy"
#segment 42

#include "apricotosint.asm"
#include "osutil.asm"
#include "memutil.asm"
#include "fsbuf.asm"
#include "fsdriver.asm"
#include "diskalloc.asm"
#include "fsdir.asm"
#include "fsread.asm"
#include "fsdel.asm"


;
; CP: copy a file within the working directory.
; $a8 - The segment of the argument string ("SRC DST")
; $a9 - The segment local address of the argument string
;
; Returns:
; $a8 - Status: 0, 2 (not found), 3 (destination exists),
;       4/12 (bad name), 5 (directory full), 6 (disk full),
;       9 (not a file)
;
; Notes:
; If the disk fills up, every sector allocated for the copy is freed
; again (the bitmap on disk is never changed) and nothing is created.
;
; Volatile registers:
; $a8-$a15
;
COPY:
    ASET 10
    OS_SYSCALL FSDEL_PARSE_TWO
    ASET 8
    BRnp CP_RET

    OS_SYSCALL FSDIR_LOAD_CWD

    ; The destination must not exist
    ASET 8
    LARh FSBUF_NAMEBUF2
    ASET 9
    LARl FSBUF_NAMEBUF2
    ASET 10
    OS_SYSCALL FSDIR_FIND_ENTRY
    ASET 8
    BRz CP_EXISTS

    OS_SYSCALL FSDIR_FIND_FREE_ENTRY
    ASET 8
    BRnp CP_RET

    ASET 10
    OS_SYSCALL CP_BODY ; $a9 = the free entry
    JMP CP_RET

    CP_EXISTS:
    ASET 8
    LARl 3

    CP_RET:
    ASET 9
    OS_SYSCALL_RET


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

;
; COPY helper: copy the file named in FSBUF_NAMEBUF to a new file named
; in FSBUF_NAMEBUF2, using a given free entry of FSBUF_DIRBUF (which
; holds the working directory).
; $a9 - The offset of the free entry in FSBUF_DIRBUF
;
; Returns:
; $a8 - Status code
;
; Registers used:
; $a0 - Free entry offset    $a2 - Track of the new metadata sector
; $a1 - Source flags byte    $a3 - Sector of the new metadata sector
; $a4 - Metadata slot offset
;
CP_BODY:
    ASET 8
    OS_SYSCALL OSUTIL_PUSHREGS
    ASET 9
    SPUSH
    ASET 0
    SPOP           ; $a0 = free entry offset

    ; Open the source (this doesn't reload FSBUF_DIRBUF, so the free entry
    ; stays valid). Its flags go into $a1, its metadata into FSBUF_METABUF2.: its metadata goes into FSBUF_METABUF2
    ASET 8
    LARh FSBUF_NAMEBUF
    ASET 9
    LARl FSBUF_NAMEBUF
    ASET 10
    OS_SYSCALL FSREAD_OPEN_FILE
    ASET 8
    BRnp CP_BODY_RET
    LAh FSBUF_DIRBUF
    ASET 9
    STal
    ASET 1
    LD
    ASET 8
    LARh FSBUF_METABUF
    ASET 9
    LARh FSBUF_METABUF2
    ASET 10
    OS_SYSCALL MEMUTIL_SEGCPY

    ; Allocate the new metadata sector
    ASET 8
    OS_SYSCALL DISKALLOC_AUTO_ALLOCATE_SECTOR
    ASET 8
    BRnp CP_BODY_RET
    ASET 9
    SPUSH
    ASET 2
    SPOP
    ASET 10
    SPUSH
    ASET 3
    SPOP

    ASET 8
    OS_SYSCALL CP_NEWMETA

    ; Copy every data block: for each used slot of the source ($a4 = 2,
    ; 4, ... 254), read the block, allocate a new sector, record it in the
    ; new metadata and write the block there
    ASET 4
    LARl 2
    CP_LP:
        ASET 8
        LARh FSBUF_METABUF2
        ASET 4
        SPUSH
        ASET 9
        SPOP
        ASET 10
        OS_SYSCALL FSDIR_ENTRY_TS
        ASET 8
        BRz CP_NEXT    ; Unused slot
        ASET 10
        LARh FSBUF_DATABUF
        ASET 11
        OS_SYSCALL FS_READ_SECTOR

        ASET 8
        OS_SYSCALL DISKALLOC_AUTO_ALLOCATE_SECTOR
        ASET 8
        BRnp CP_FULL

        LAh FSBUF_METABUF
        ASET 4
        STal
        ASET 9
        ST
        ASET 4
        ADD 1
        STal
        ASET 10
        ST
        ASET 4
        NOT
        ADD 1
        NOT            ; $a4 -= 1: back to the start of the slot

        ; FS_WRITE_SECTOR($a8 = track, $a9 = sector), from the allocator's
        ; $a9 = track, $a10 = sector
        ASET 9
        SPUSH
        ASET 8
        SPOP
        ASET 10
        SPUSH
        ASET 9
        SPOP
        ASET 10
        LARh FSBUF_DATABUF
        ASET 11
        OS_SYSCALL FS_WRITE_SECTOR

        CP_NEXT:
        ASET 4
        ADD 2
        BRnp CP_LP

    ASET 8
    OS_SYSCALL CP_FINISH

    ASET 8
    AND 0
    JMP CP_BODY_RET

    CP_FULL:
    ASET 8
    OS_SYSCALL CP_ROLLBACK
    ASET 8
    LARl 6

    CP_BODY_RET:
    ASET 9
    OS_SYSCALL OSUTIL_POPREGS
    ASET 9
    OS_SYSCALL_RET


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

;
; COPY helper: clear FSBUF_METABUF for the new file's metadata, and
; give it the source's size (from FSBUF_METABUF2).
;
CP_NEWMETA:
    ; New metadata: same size, no blocks yet
    ASET 8
    LARh FSBUF_METABUF
    ASET 9
    AND 0
    ASET 10
    OS_SYSCALL MEMUTIL_SEGSET
    ASET 8
    LARh FSBUF_METABUF2
    ASET 9
    AND 0
    ASET 10
    LARh FSBUF_METABUF
    ASET 11
    AND 0
    ASET 12
    AND 0
    ADD 2
    ASET 13
    OS_SYSCALL MEMUTIL_MEMCPY

    ASET 8
    OS_SYSCALL_RET


;
; COPY helper: flush the bitmap, write the new metadata sector ($a2,
; $a3), then add the new directory entry. Uses CP_BODY's registers.
; Falls through into CP_ADD_ENTRY, which returns.
;
CP_FINISH:
    ; Flush the bitmap, write the metadata, then add the entry
    ASET 8
    OS_SYSCALL DISKALLOC_FLUSH_BITMAP
    ASET 2
    SPUSH
    ASET 8
    SPOP
    ASET 3
    SPUSH
    ASET 9
    SPOP
    ASET 10
    LARh FSBUF_METABUF
    ASET 11
    OS_SYSCALL FS_WRITE_SECTOR

;
; COPY helper: fill in the new directory entry ($a0) from the source
; flags ($a1, executable bit only), the metadata sector ($a2, $a3) and
; FSBUF_NAMEBUF2, then write the directory back. Uses CP_BODY's registers.
;
CP_ADD_ENTRY:
    ASET 9
    LARl 0x40
    SPUSH
    ASET 1
    SPUSH
    ASET 9
    SPOP
    SPOP AND       ; $a9 = executable bit
    ASET 10
    LARl 0xA0
    SPUSH
    ASET 9
    SPOP OR
    ASET 2
    SPUSH
    ASET 9
    SPOP OR        ; $a9 = 0x80 | file | exec | track

    ; Store the flags/track byte and the sector byte
    LAh FSBUF_DIRBUF
    ASET 0
    STal
    ASET 9
    ST
    ASET 0
    SPUSH
    ASET 11
    SPOP
    ADD 1
    STal
    ASET 3
    SPUSH
    ASET 9
    SPOP
    ST

    ASET 11
    ADD 1          ; $a11 = name field
    ASET 10
    LARh FSBUF_DIRBUF
    ASET 8
    LARh FSBUF_NAMEBUF2
    ASET 9
    LARl FSBUF_NAMEBUF2
    ASET 12
    LARl 6
    ASET 13
    OS_SYSCALL MEMUTIL_MEMCPY

    ASET 8
    OS_SYSCALL FSDIR_STORE_CWD
    ASET 8
    OS_SYSCALL_RET


;
; COPY helper: free every sector allocated so far for the copy
; (the blocks recorded in FSBUF_METABUF, and the metadata sector
; $a2, $a3). Only the in-memory bitmap is changed. Uses CP_BODY's
; registers.
;
CP_ROLLBACK:
    ASET 4
    LARl 2
    CP_RB_LP:
        ASET 8
        LARh FSBUF_METABUF
        ASET 4
        SPUSH
        ASET 9
        SPOP
        ASET 10
        OS_SYSCALL FSDIR_ENTRY_TS
        ASET 8
        BRz CP_RB_NEXT
        ASET 10
        OS_SYSCALL DISKALLOC_FREE_SECTOR
        CP_RB_NEXT:
        ASET 4
        ADD 2
        BRnp CP_RB_LP

    ASET 2
    SPUSH
    ASET 8
    SPOP
    ASET 3
    SPUSH
    ASET 9
    SPOP
    ASET 10
    OS_SYSCALL DISKALLOC_FREE_SECTOR
    ASET 8
    OS_SYSCALL_RET
