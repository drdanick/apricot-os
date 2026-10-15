; asmsyntax=apricos
; ===================================
; ==                               ==
; ==  ApricotOS Filesystem         ==
; ==  file reading routines        ==
; ==                               ==
; ===================================
;
; A file's directory entry points to its metadata sector:
;  bytes 0-1 - file size, little-endian (at most 32512)
;  bytes 2-  - up to 127 (track, sector) pairs for the data sectors,
;              in order; track 0 marks an unused slot
;

#name "fsread"
#segment 25

#include "apricotosint.asm"
#include "osutil.asm"
#include "fsbuf.asm"
#include "fsdriver.asm"
#include "fsdir.asm"
#include "portout.asm"


;
; Print a file (CAT). Bytes 0x20-0x7E and newlines are printed as they
; are; any other byte is printed as '.'.
; $a8 - The segment of the argument string (the file name)
; $a9 - The segment local address of the argument string
;
; Returns:
; $a8 - Status code
;
; Volatile registers:
; $a8-$a15
;
CAT:
    ASET 10
    LARh FSBUF_NAMEBUF
    ASET 11
    LARl FSBUF_NAMEBUF
    ASET 12
    OS_SYSCALL FSDIR_PARSE_NAME
    ASET 8
    BRnp CAT_RET

    OS_SYSCALL FSDIR_LOAD_CWD
    ASET 8
    LARh FSBUF_NAMEBUF
    ASET 9
    LARl FSBUF_NAMEBUF
    ASET 10
    OS_SYSCALL OPEN_FILE
    ASET 8
    BRnp CAT_RET

    OS_SYSCALL OSUTIL_PUSHREGS

    ; $a0:$a1 = bytes remaining (high:low), $a2 = metadata pointer offset.
    ; Each block prints 256 bytes while $a0 > 0, then the final $a1 bytes.
    LAh FSBUF_METABUF
    LAl 0
    ASET 1
    LD
    LAl 1
    ASET 0
    LD
    ASET 2
    LARl 2

    CAT_LP:
        ; Stop when no bytes remain
        ASET 0
        SPUSH
        ASET 1
        SPUSH
        ASET 3
        SPOP
        SPOP OR
        BRz CAT_DONE

        ; Read the next data sector into FSBUF_DATABUF
        LAh FSBUF_METABUF
        ASET 2
        STal
        ASET 8
        LD
        BRz CAT_DONE   ; Unused slot: the metadata is shorter than the size
        ASET 2
        ADD 1
        STal
        ASET 10
        LARl 0x3F
        SPUSH
        ASET 9
        LD
        SPOP AND
        ASET 10
        LARh FSBUF_DATABUF
        ASET 11
        OS_SYSCALL FS_READ_SECTOR

        ; Print 256 bytes, or the remainder if less than 256 bytes remain
        ASET 0
        BRz CAT_LAST
        NOT
        ADD 1
        NOT            ; $a0 -= 1
        ASET 9
        AND 0          ; Count 0 = 256 bytes
        JMP CAT_PRINT
        CAT_LAST:
        ASET 1
        SPUSH
        ASET 9
        SPOP           ; Count = $a1
        ASET 1
        AND 0          ; Nothing remains after this block
        CAT_PRINT:
        ASET 8
        LARh FSBUF_DATABUF
        ASET 10
        OS_SYSCALL PUTBYTES

        ASET 2
        ADD 1
        BRnp CAT_LP    ; Stop after the last pair (offset wraps to 0)

    CAT_DONE:
    ASET 8
    OS_SYSCALL OSUTIL_POPREGS
    ASET 8
    AND 0

    CAT_RET:
    ASET 9
    OS_SYSCALL_RET


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

;
; Open a file in the working directory: find its entry in
; FSBUF_DIRBUF (which must hold the working directory) and read its
; metadata sector into FSBUF_METABUF.
; $a8 - The segment of the 6-byte name
; $a9 - The segment local address of the 6-byte name
;
; Returns:
; $a8 - Status: 0, 2 (not found) or 9 (not a file)
; $a9 - The offset of the file's entry in FSBUF_DIRBUF
;
; Volatile registers:
; $a8-$a15
;
OPEN_FILE:
    ASET 10
    OS_SYSCALL FSDIR_FIND_ENTRY
    ASET 8
    BRnp OF_RET

    ; The entry must be a file (bit 5 set)
    LAh FSBUF_DIRBUF
    ASET 9
    STal
    ASET 10
    LD
    SHFl 2
    BRn OF_FILE
    ASET 8
    LARl 9
    JMP OF_RET

    OF_FILE:
    ASET 9
    SPUSH
    ASET 8
    LARh FSBUF_DIRBUF
    ASET 10
    OS_SYSCALL FSDIR_ENTRY_TS
    ASET 10
    LARh FSBUF_METABUF
    ASET 11
    OS_SYSCALL FS_READ_SECTOR
    ASET 9
    SPOP
    ASET 8
    AND 0

    OF_RET:
    ASET 10
    OS_SYSCALL_RET


;
; Print bytes from the start of a segment. Bytes 0x20-0x7E and
; newlines are printed as they are; any other byte is printed as '.'.
; $a8 - The segment
; $a9 - The number of bytes to print (0 = 256)
;
; Volatile registers:
; $a8-$a12
;
PUTBYTES:
    ASET 8
    STah
    ASET 10        ; $a10 = index
    AND 0
    PB_LP:
        ASET 10
        STal
        ASET 11
        LD
        BRn PB_DOT     ; >= 0x80

        SPUSH
        XOR 10
        BRz PB_NL      ; Newline
        XOR 10         ; Restore the character

        ASET 12
        LARl 0xE0
        SPOP ADD       ; $a12 = c - 0x20
        BRn PB_DOT     ; Control character

        ASET 11
        SPUSH
        ASET 12
        SPOP
        ADD 1
        BRn PB_DOT     ; 0x7F
        ASET 11
        JMP PB_OUT

        PB_NL:
        SPOP           ; Restore the newline
        JMP PB_OUT

        PB_DOT:
        ASET 11
        LARl 0x2E

        PB_OUT:
        PORTOUT_TTY_WRITE

        ; Stop when index == count (count 0 wraps around after 256 bytes)
        ASET 10
        ADD 1
        SPUSH
        ASET 9
        SPUSH
        ASET 12
        SPOP
        SPOP XOR
        BRnp PB_LP

    ASET 10
    OS_SYSCALL_RET
