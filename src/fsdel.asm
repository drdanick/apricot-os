; asmsyntax=apricos
; ===================================
; ==                               ==
; ==  ApricotOS Filesystem         ==
; ==  remove and rename routines   ==
; ==                               ==
; ===================================
;

#name "fsdel"
#segment 40

#include "apricotosint.asm"
#include "osutil.asm"
#include "memutil.asm"
#include "fsbuf.asm"
#include "fsdriver.asm"
#include "diskalloc.asm"
#include "fsdir.asm"


;
; RM: remove a file or an empty directory from the working directory.
; A file's data sectors and its metadata sector are freed.
; The directory entry is cleared on disk before the bitmap is flushed.
; $a8 - The segment of the argument string (the name)
; $a9 - The segment local address of the argument string
;
; Returns:
; $a8 - Status: 0, 2 (not found), 4/12 (bad name),
;       10 (directory not empty)
;
; Volatile registers:
; $a8-$a15
;
; Registers used:
; $a0 - Entry offset, then metadata slot offset
; $a1 - Entry flags byte
; $a2 - Track of the entry's sector
; $a3 - Sector of the entry's sector
;
REMOVE:
    ASET 10
    LARh FSBUF_NAMEBUF
    ASET 11
    LARl FSBUF_NAMEBUF
    ASET 12
    OS_SYSCALL FSDIR_PARSE_NAME
    ASET 8
    BRnp RM_RET

    OS_SYSCALL FSDIR_LOAD_CWD
    ASET 8
    LARh FSBUF_NAMEBUF
    ASET 9
    LARl FSBUF_NAMEBUF
    ASET 10
    OS_SYSCALL FSDIR_FIND_ENTRY
    ASET 8
    BRnp RM_RET

    OS_SYSCALL OSUTIL_PUSHREGS
    ASET 9
    SPUSH
    ASET 0
    SPOP           ; $a0 = entry offset
    LAh FSBUF_DIRBUF
    STal
    ASET 1
    LD             ; $a1 = flags byte

    ASET 8
    LARh FSBUF_DIRBUF
    ASET 0
    SPUSH
    ASET 9
    SPOP
    ASET 10
    OS_SYSCALL FSDIR_ENTRY_TS
    ASET 8
    SPUSH
    ASET 2
    SPOP
    ASET 9
    SPUSH
    ASET 3
    SPOP

    ; Read the entry's sector (directory or file metadata) into FSBUF_METABUF
    ASET 10
    LARh FSBUF_METABUF
    ASET 11
    OS_SYSCALL FS_READ_SECTOR

    ASET 1
    SPUSH
    ASET 8
    SPOP
    SHFl 2
    BRn RM_UNLINK  ; Files can always be removed

    ; A directory must be empty
    LAh FSBUF_METABUF
    ASET 8
    AND 0
    RM_CHK:
        STal
        ASET 9
        LD
        BRn RM_NOTEMPTY
        ASET 8
        ADD 8
        BRnp RM_CHK

    RM_UNLINK:
    ; Clear the directory entry and write the directory back
    ASET 8
    LARh FSBUF_DIRBUF
    ASET 0
    SPUSH
    ASET 9
    SPOP
    ASET 10
    LARl 8
    ASET 11
    AND 0
    ASET 12
    OS_SYSCALL MEMUTIL_MEMSET
    ASET 8
    OS_SYSCALL FSDIR_STORE_CWD

    ASET 8
    OS_SYSCALL RM_FREE

    ASET 8
    AND 0
    JMP RM_POPRET

    RM_NOTEMPTY:
    ASET 8
    LARl 10

    RM_POPRET:
    ASET 9
    OS_SYSCALL OSUTIL_POPREGS

    RM_RET:
    ASET 9
    OS_SYSCALL_RET


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

;
; REMOVE helper: free the removed entry's sectors (the data sectors
; listed in FSBUF_METABUF if it is a file, then the entry's own sector
; $a2, $a3) and flush the bitmap. Uses REMOVE's $a0-$a3.
;
RM_FREE:
    ; Free a file's data sectors
    ASET 1
    SPUSH
    ASET 8
    SPOP
    SHFl 2
    BRzp RM_FREE_SELF
    ASET 0
    LARl 2
    RM_FREE_LP:
        ASET 8
        LARh FSBUF_METABUF
        ASET 0
        SPUSH
        ASET 9
        SPOP
        ASET 10
        OS_SYSCALL FSDIR_ENTRY_TS
        ASET 8
        BRz RM_FREE_NEXT   ; Unused slot
        ASET 10
        OS_SYSCALL DISKALLOC_FREE_SECTOR
        RM_FREE_NEXT:
        ASET 0
        ADD 2
        BRnp RM_FREE_LP

    RM_FREE_SELF:
    ; Free the directory or metadata sector itself
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
    OS_SYSCALL DISKALLOC_FLUSH_BITMAP

    ASET 8
    OS_SYSCALL_RET


;
; Split a two-word argument string at its first space, which is
; replaced with a NUL. The string must not cross a page.
; $a8 - The segment of the argument string
; $a9 - The segment local address of the argument string
;
; Returns:
; $a10 - The segment of the second word
; $a11 - The segment local address of the second word
; $a12 - Status: 0, or 12 (missing argument) if there is no space
;
; Volatile registers:
; $a10-$a13 ($a8 and $a9 are preserved)
;
SPLIT_ARG:
    ASET 8
    STah
    ASET 9
    SPUSH
    ASET 11
    SPOP
    SA_LP:
        ASET 11
        STal
        ASET 12
        LD
        BRz SA_MISSING
        SPUSH
        ASET 13
        LARl 0xE0
        SPOP ADD
        BRz SA_FOUND
        ASET 11
        ADD 1
        JMP SA_LP

    SA_FOUND:
    ASET 12
    AND 0
    ST
    ASET 11
    ADD 1
    ASET 8
    SPUSH
    ASET 10
    SPOP
    JMP SA_RET

    SA_MISSING:
    ASET 12
    LARl 12

    SA_RET:
    ASET 13
    OS_SYSCALL_RET


;
; Parse a two-word argument string ("ONE TWO") into FSBUF_NAMEBUF
; and FSBUF_NAMEBUF2.
; $a8 - The segment of the argument string
; $a9 - The segment local address of the argument string
;
; Returns:
; $a8 - Status: 0, 4 (bad name) or 12 (missing argument)
;
; Volatile registers:
; $a8-$a15
;
PARSE_TWO:
    ASET 13
    OS_LOCALSYSCALL SPLIT_ARG
    ASET 12
    BRz PT_SPLIT_OK
    SPUSH
    ASET 8
    SPOP
    JMP PT_RET

    PT_SPLIT_OK:
    ASET 10
    SPUSH
    ASET 11
    SPUSH          ; Save the second word
    ASET 10
    LARh FSBUF_NAMEBUF
    ASET 11
    LARl FSBUF_NAMEBUF
    ASET 12
    OS_SYSCALL FSDIR_PARSE_NAME
    ASET 9
    SPOP
    ASET 10
    SPOP
    ASET 8
    BRnp PT_RET
    ASET 10
    SPUSH
    ASET 8
    SPOP
    ASET 10
    LARh FSBUF_NAMEBUF2
    ASET 11
    LARl FSBUF_NAMEBUF2
    ASET 12
    OS_SYSCALL FSDIR_PARSE_NAME

    PT_RET:
    ASET 9
    OS_SYSCALL_RET


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

;
; MV: rename an entry of the working directory.
; $a8 - The segment of the argument string ("OLD NEW")
; $a9 - The segment local address of the argument string
;
; Returns:
; $a8 - Status: 0, 2 (not found), 3 (new name exists),
;       4/12 (bad name)
;
; Volatile registers:
; $a8-$a15
;
RENAME:
    ASET 10
    OS_SYSCALL PARSE_TWO
    ASET 8
    BRnp MV_RET

    OS_SYSCALL FSDIR_LOAD_CWD

    ; The new name must not exist
    ASET 8
    LARh FSBUF_NAMEBUF2
    ASET 9
    LARl FSBUF_NAMEBUF2
    ASET 10
    OS_SYSCALL FSDIR_FIND_ENTRY
    ASET 8
    BRz MV_EXISTS

    ASET 8
    LARh FSBUF_NAMEBUF
    ASET 9
    LARl FSBUF_NAMEBUF
    ASET 10
    OS_SYSCALL FSDIR_FIND_ENTRY
    ASET 8
    BRnp MV_RET

    ; Overwrite the name field of the entry
    ASET 9
    ADD 2
    SPUSH
    ASET 11
    SPOP
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
    AND 0
    JMP MV_RET

    MV_EXISTS:
    ASET 8
    LARl 3

    MV_RET:
    ASET 9
    OS_SYSCALL_RET
