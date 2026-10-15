; asmsyntax=apricos
; ===================================
; ==                               ==
; ==  ApricotOS Filesystem         ==
; ==  creation and write routines  ==
; ==                               ==
; ===================================
;
; Write ordering (so that a crash can only leak sectors):
; 1. write the contents of newly allocated sectors,
; 2. flush the space bitmap,
; 3. write the structure that references them (directory or metadata).
;
; Segment 34: TOUCH, MKDIR, CREATE
; Segment 35: WRITE
; Segment 36: APPEND
; Segment 37: AP_CHECKSIZE, AP_GETBLOCK
; Segment 38: AP_COPY
;

#name "fswrite"
#segment 34

#include "apricotosint.asm"
#include "osutil.asm"
#include "memutil.asm"
#include "fsbuf.asm"
#include "fsdriver.asm"
#include "diskalloc.asm"
#include "fsdir.asm"
#include "fsread.asm"


;
; TOUCH: create an empty file in the working directory.
; $a8 - The segment of the argument string (the name)
; $a9 - The segment local address of the argument string
;
; Returns:
; $a8 - Status code
;
TOUCH:
    ASET 10
    LARl 0x20
    JMP CREATE

;
; MKDIR: create an empty directory in the working directory.
; $a8 - The segment of the argument string (the name)
; $a9 - The segment local address of the argument string
;
; Returns:
; $a8 - Status code
;
MKDIR:
    ASET 10
    AND 0
    ; Falls through into CREATE

;
; Create an empty file or directory in the working directory.
; $a8  - The segment of the name string
; $a9  - The segment local address of the name string
; $a10 - The type: 0x20 for a file, 0 for a directory
;
; Returns:
; $a8 - Status: 0, 3 (exists), 4/12 (bad name), 5 (directory full),
;       6 (disk full)
;
; Volatile registers:
; $a8-$a15
;
; Stack while running (pushed in this order): type, entry offset, track,
; sector. The CR_POPn_RET exits pop what has been pushed so far.
;
CREATE:
    ASET 10
    SPUSH          ; Save the type

    LARh FSBUF_NAMEBUF
    ASET 11
    LARl FSBUF_NAMEBUF
    ASET 12
    OS_SYSCALL FSDIR_PARSE_NAME
    ASET 8
    BRnp CR_POP1_RET

    OS_SYSCALL FSDIR_LOAD_CWD

    ; The name must not exist yet
    ASET 8
    LARh FSBUF_NAMEBUF
    ASET 9
    LARl FSBUF_NAMEBUF
    ASET 10
    OS_SYSCALL FSDIR_FIND_ENTRY
    ASET 8
    BRz CR_EXISTS

    OS_SYSCALL FSDIR_FIND_FREE_ENTRY
    ASET 8
    BRnp CR_POP1_RET
    ASET 9
    SPUSH          ; Save the entry offset

    ASET 8
    OS_SYSCALL DISKALLOC_AUTO_ALLOCATE_SECTOR
    ASET 8
    BRnp CR_POP2_RET
    ASET 9
    SPUSH          ; Save the track
    ASET 10
    SPUSH          ; Save the sector

    ; Write a zeroed sector (empty directory, or metadata with size 0)
    ASET 8
    LARh FSBUF_DATABUF
    ASET 9
    AND 0
    ASET 10
    OS_SYSCALL MEMUTIL_SEGSET
    ASET 9
    SPOP           ; Peek the sector and track (pop, then push them back)
    ASET 8
    SPOP
    SPUSH
    ASET 9
    SPUSH
    ASET 10
    LARh FSBUF_DATABUF
    ASET 11
    OS_SYSCALL FS_WRITE_SECTOR

    ASET 8
    OS_SYSCALL DISKALLOC_FLUSH_BITMAP

    ; Fill in the directory entry
    ASET 11
    SPOP           ; $a11 = sector
    ASET 10
    SPOP           ; $a10 = track
    ASET 9
    SPOP           ; $a9 = entry offset
    ASET 12
    SPOP           ; $a12 = type
    ASET 13
    LARl 0x80
    SPUSH
    ASET 12
    SPOP OR
    ASET 10
    SPUSH
    ASET 12
    SPOP OR        ; $a12 = 0x80 | type | track

    LAh FSBUF_DIRBUF
    ASET 9
    STal
    ASET 12
    ST
    ASET 9
    ADD 1
    STal
    ASET 11
    ST

    ASET 9
    ADD 1
    SPUSH
    ASET 11
    SPOP           ; $a11 = offset of the name field
    ASET 10
    LARh FSBUF_DIRBUF
    ASET 8
    LARh FSBUF_NAMEBUF
    ASET 9
    LARl FSBUF_NAMEBUF
    ASET 12
    LARl 6
    ASET 13
    OS_SYSCALL MEMUTIL_MEMCPY

    ASET 8
    OS_SYSCALL FSDIR_STORE_CWD

    ASET 8
    AND 0
    JMP CR_RET

    CR_EXISTS:
    ASET 8
    LARl 3
    JMP CR_POP1_RET

    CR_POP2_RET:
    ASET 9
    SPOP
    CR_POP1_RET:
    ASET 9
    SPOP
    CR_RET:
    ASET 9
    OS_SYSCALL_RET


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

;
; WRITE: append a line of text to a file, creating it if needed.
; $a8 - The segment of the argument string ("NAME TEXT")
; $a9 - The segment local address of the argument string
;
; Returns:
; $a8 - Status code
;
; Notes:
; The argument string is modified: the first space becomes a NUL and
; the terminating NUL becomes a newline.
;
; Volatile registers:
; $a8-$a15
;
WRITE:
    ASET 8
    STah
    ASET 9
    SPUSH
    ASET 10
    SPOP           ; $a10 = scan pointer

    ; Find the first space
    WR_SCAN:
        ASET 10
        STal
        ASET 11
        LD
        BRz WR_MISSING
        SPUSH
        ASET 12
        LARl 0xE0
        SPOP ADD       ; c - 0x20: zero for a space
        BRz WR_SPLIT
        ASET 10
        ADD 1
        JMP WR_SCAN

    WR_MISSING:
    ASET 8
    LARl 12
    JMP WR_RET

    WR_SPLIT:
    ASET 11
    AND 0
    ST             ; Terminate the name
    ASET 10
    ADD 1          ; $a10 = start of the text

    ; Find the end of the text, counting its length in $a12
    ASET 12
    AND 0
    ASET 10
    SPUSH
    ASET 13
    SPOP
    WR_LEN:
        ASET 13
        STal
        ASET 11
        LD
        BRz WR_LEN_END
        ASET 13
        ADD 1
        ASET 12
        ADD 1
        JMP WR_LEN
    WR_LEN_END:
    ASET 11
    LARl 0x0A
    ST             ; Replace the NUL with a newline
    ASET 12
    ADD 1          ; Count the newline (the command line is at most 128
                   ; characters, so this cannot exceed 255)

    ; Save the name address, text address and count across CREATE
    ASET 8
    SPUSH
    ASET 9
    SPUSH
    ASET 10
    SPUSH
    ASET 12
    SPUSH

    ; Create the file; it may already exist
    ASET 10
    LARl 0x20
    ASET 11
    OS_SYSCALL CREATE
    ASET 8
    BRz WR_APPEND
    XOR 3          ; Status 3 (already exists) is fine too
    BRz WR_APPEND
    XOR 3          ; Restore any other status and return it
    ASET 9
    SPOP
    SPOP
    SPOP
    SPOP
    JMP WR_RET

    ; APPEND(name = $a8:$a9, data = $a8:text, count): the text is in the
    ; same segment as the name
    WR_APPEND:
    ASET 12
    SPOP
    ASET 11
    SPOP
    ASET 9
    SPOP
    ASET 8
    SPOP
    SPUSH
    ASET 10
    SPOP
    ASET 13
    OS_SYSCALL APPEND

    WR_RET:
    ASET 9
    OS_SYSCALL_RET


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

;
; Append data to a file in the working directory.
; $a8  - The segment of the name string
; $a9  - The segment local address of the name string
; $a10 - The segment of the data
; $a11 - The segment local address of the data
; $a12 - The number of bytes to append (1-255)
;
; Returns:
; $a8 - Status: 0, 2 (not found), 4/12 (bad name), 6 (disk full),
;       7 (file too big), 9 (not a file)
;
; Notes:
; If the disk fills up part way, the data written so far is kept
; and the status is 6.
;
; Volatile registers:
; $a8-$a15
;
; Registers used during the append (shared with the AP_ helpers):
; $a0 - Status          $a4 - Bytes remaining
; $a1 - Entry offset    $a5 - File size (low byte)
; $a2 - Data segment    $a6 - File size (high byte)
; $a3 - Data address    $a7 - Metadata slot offset of the current block
;
APPEND:
    ASET 15
    OS_SYSCALL OSUTIL_PUSHREGSANDCOPY

    ASET 10
    LARh FSBUF_NAMEBUF
    ASET 11
    LARl FSBUF_NAMEBUF
    ASET 12
    OS_SYSCALL FSDIR_PARSE_NAME
    ASET 8
    BRnp AP_RET

    OS_SYSCALL FSDIR_LOAD_CWD
    ASET 8
    LARh FSBUF_NAMEBUF
    ASET 9
    LARl FSBUF_NAMEBUF
    ASET 10
    OS_SYSCALL FSREAD_OPEN_FILE
    ASET 8
    BRnp AP_RET

    ASET 9
    SPUSH
    ASET 1
    SPOP           ; $a1 = entry offset
    ; $a6:$a5 = current file size
    LAh FSBUF_METABUF
    LAl 0
    ASET 5
    LD
    LAl 1
    ASET 6
    LD

    ASET 8
    OS_SYSCALL AP_CHECKSIZE
    ASET 8
    BRnp AP_RET

    ; Fill one block per pass until no bytes remain ($a0 = status 0)
    ASET 0
    AND 0
    AP_LP:
        ASET 4
        BRz AP_DONE
        ASET 8
        OS_SYSCALL AP_GETBLOCK
        ASET 8
        BRnp AP_FULL
        OS_SYSCALL AP_COPY
        JMP AP_LP

    ; Disk full: keep what was written, and return status 6
    AP_FULL:
    SPUSH
    ASET 0
    SPOP

    AP_DONE:
    ; Store the new size, flush the bitmap, then write the metadata
    LAh FSBUF_METABUF
    LAl 0
    ASET 5
    ST
    LAl 1
    ASET 6
    ST

    ASET 8
    OS_SYSCALL DISKALLOC_FLUSH_BITMAP

    ASET 8
    LARh FSBUF_DIRBUF
    ASET 1
    SPUSH
    ASET 9
    SPOP
    ASET 10
    OS_SYSCALL FSDIR_ENTRY_TS
    ASET 10
    LARh FSBUF_METABUF
    ASET 11
    OS_SYSCALL FS_WRITE_SECTOR

    ASET 0
    SPUSH
    ASET 8
    SPOP

    AP_RET:
    ASET 9
    OS_SYSCALL OSUTIL_POPREGS
    ASET 9
    OS_SYSCALL_RET


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

;
; APPEND helper: check that size ($a6:$a5) + count ($a4) <= 32512 (0x7F00).
; Uses APPEND's registers.
;
; Returns:
; $a8 - Status: 0 or 7 (file too big)
;
AP_CHECKSIZE:
    ASET 5
    SPUSH
    ASET 4
    SPUSH
    ASET 8
    SPOP
    SPOP ADD
    PRTin 4
    SHFr 3         ; $a8 = carry
    SPUSH
    ASET 6
    SPUSH
    ASET 8
    SPOP
    SPOP ADD       ; $a8 = new size (high byte)
    BRn AP_TOOBIG  ; >= 0x8000
    ADD 1
    BRzp AP_SIZE_OK ; High byte < 0x7F (only 0x7F + 1 is negative)

    ; High byte is 0x7F: the low byte must be 0
    ASET 5
    SPUSH
    ASET 4
    SPUSH
    ASET 8
    SPOP
    SPOP ADD
    BRz AP_SIZE_OK

    AP_TOOBIG:
    ASET 8
    LARl 7
    JMP AP_CHECKSIZE_RET

    AP_SIZE_OK:
    ASET 8
    AND 0

    AP_CHECKSIZE_RET:
    ASET 9
    OS_SYSCALL_RET


;
; APPEND helper: get the block the next byte goes into into
; FSBUF_DATABUF. If the size is a multiple of 256, a new block is
; allocated (and zeroed); otherwise the last block is read.
; Sets $a7 to the block's metadata slot offset. Uses APPEND's registers.
;
; A new block's (track, sector) is stored in FSBUF_METABUF straight away,
; but the metadata only reaches the disk at the end of APPEND, after the
; data and the bitmap.
;
; Returns:
; $a8 - Status: 0 or 6 (disk full)
;
AP_GETBLOCK:
    ASET 6
    SPUSH
    ASET 7
    SPOP
    SHFl 1
    ADD 2          ; $a7 = 2 + 2 * block index

    ASET 5
    BRnp AP_GB_READ

    ASET 8
    OS_SYSCALL DISKALLOC_AUTO_ALLOCATE_SECTOR
    ASET 8
    BRnp AP_GB_RET

    ; Store the new block's track ($a9) and sector ($a10) in its slot
    LAh FSBUF_METABUF
    ASET 7
    STal
    ASET 9
    ST
    ASET 7
    ADD 1
    STal
    ASET 10
    ST
    ASET 7
    NOT
    ADD 1
    NOT            ; $a7 -= 1: back to the start of the slot

    ASET 8
    LARh FSBUF_DATABUF
    ASET 9
    AND 0
    ASET 10
    OS_SYSCALL MEMUTIL_SEGSET
    JMP AP_GB_OK

    AP_GB_READ:
    ASET 8
    LARh FSBUF_METABUF
    ASET 7
    SPUSH
    ASET 9
    SPOP
    ASET 10
    OS_SYSCALL FSDIR_ENTRY_TS
    ASET 10
    LARh FSBUF_DATABUF
    ASET 11
    OS_SYSCALL FS_READ_SECTOR

    AP_GB_OK:
    ASET 8
    AND 0

    AP_GB_RET:
    ASET 9
    OS_SYSCALL_RET


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

;
; APPEND helper: copy as many bytes as fit into the current block
; (FSBUF_DATABUF, slot $a7), write the block, and advance the data
; pointer, the byte count and the file size. Uses APPEND's registers.
;
AP_COPY:
    ; n = min(remaining, 256 - size low byte), in $a12.
    ; remaining > space exactly when ~space + remaining carries.
    ASET 5
    SPUSH
    ASET 12
    SPOP
    NOT
    ADD 1          ; $a12 = space left (0 = a whole block)
    BRz AP_N_REM
    ASET 12
    SPUSH
    ASET 13
    SPOP
    NOT
    SPUSH
    ASET 4
    SPUSH
    ASET 13
    SPOP
    SPOP ADD       ; carry if remaining > space
    PRTin 4
    AND 8
    BRnp AP_N_DONE
    AP_N_REM:
    ASET 4
    SPUSH
    ASET 12
    SPOP
    AP_N_DONE:
    ASET 12
    SPUSH          ; Save n

    ; Copy n bytes from $a2:$a3 to FSBUF_DATABUF + size low byte
    ASET 2
    SPUSH
    ASET 8
    SPOP
    ASET 3
    SPUSH
    ASET 9
    SPOP
    ASET 10
    LARh FSBUF_DATABUF
    ASET 5
    SPUSH
    ASET 11
    SPOP
    ASET 13
    OS_SYSCALL MEMUTIL_MEMCPY

    ; Write the block back
    ASET 8
    LARh FSBUF_METABUF
    ASET 7
    SPUSH
    ASET 9
    SPOP
    ASET 10
    OS_SYSCALL FSDIR_ENTRY_TS
    ASET 10
    LARh FSBUF_DATABUF
    ASET 11
    OS_SYSCALL FS_WRITE_SECTOR

    ; Advance the counters by n: leave three copies of n on the stack, one
    ; per counter. The 16-bit adds carry into the high byte via the O flag.
    ASET 12
    SPOP
    SPUSH
    SPUSH
    SPUSH

    ASET 13
    SPOP
    NOT
    ADD 1
    SPUSH
    ASET 4
    SPOP ADD       ; remaining -= n

    ASET 3
    SPOP ADD       ; data address += n
    SPUSH
    PRTin 4
    SHFr 3
    SPUSH
    ASET 2
    SPOP ADD
    ASET 3
    SPOP

    ASET 5
    SPOP ADD       ; size += n
    SPUSH
    PRTin 4
    SHFr 3
    SPUSH
    ASET 6
    SPOP ADD
    ASET 5
    SPOP

    ASET 8
    OS_SYSCALL_RET
