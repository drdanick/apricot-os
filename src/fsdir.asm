; asmsyntax=apricos
; ===================================
; ==                               ==
; ==  ApricotOS Filesystem         ==
; ==  directory routines           ==
; ==                               ==
; ==  Name parsing, directory      ==
; ==  lookup and listing.          ==
; ==                               ==
; ===================================
;
; A directory is one sector of 32 entries x 8 bytes:
;  byte 0   - bit 7: in use, bit 6: executable, bit 5: file (0 = directory),
;             bits 4-0: track
;  byte 1   - bits 5-0: sector
;  byte 2-7 - name, NUL padded (not terminated when 6 characters long)
;
; The working directory's sector is kept in FSBUF_DIRBUF; entry offsets
; returned by these routines are offsets into that buffer.
;

#name "fsdir"
#segment 21

#include "apricotosint.asm"
#include "osutil.asm"
#include "memutil.asm"
#include "fsbuf.asm"
#include "fsdriver.asm"
#include "portout.asm"


;
; Get the track and sector an 8-byte entry (directory entry or
; path stack entry) points to. The entry must not cross a page.
; $a8 - The segment of the entry
; $a9 - The segment local address of the entry
;
; Returns:
; $a8 - The track number
; $a9 - The sector number
;
; Volatile registers:
; $a8-$a10
;
ENTRY_TS:
    ASET 8
    STah
    ASET 9
    STal
    ADD 1
    ASET 10
    LARl 0x1F
    SPUSH
    ASET 8
    LD
    SPOP AND       ; $a8 = track

    ASET 9
    STal
    ASET 10
    LARl 0x3F
    SPUSH
    ASET 9
    LD
    SPOP AND       ; $a9 = sector

    ASET 10
    OS_SYSCALL_RET


;
; Get the track and sector of the working directory.
;
; Returns:
; $a8 - The track number
; $a9 - The sector number
;
; Volatile registers:
; $a8-$a10
;
PATH_TOP:
    LAh FSBUF_PATH_DEPTH
    LAl FSBUF_PATH_DEPTH
    ASET 9
    LD
    NOT            ; $a9 = depth - 1
    ADD 1
    NOT
    SHFl 3
    SPUSH
    LARl FSBUF_PATH_STACK
    SPOP ADD       ; $a9 = address of the top entry
    ASET 8
    LARh FSBUF_PATH_STACK
    ASET 10
    OS_LOCALSYSCALL ENTRY_TS
    ASET 10
    OS_SYSCALL_RET


;
; Read the working directory's sector into FSBUF_DIRBUF.
;
; Volatile registers:
; $a8-$a11
;
LOAD_CWD:
    ASET 10
    OS_LOCALSYSCALL PATH_TOP
    ASET 10
    LARh FSBUF_DIRBUF
    ASET 11
    OS_SYSCALL FS_READ_SECTOR
    ASET 8
    OS_SYSCALL_RET


;
; Write FSBUF_DIRBUF back to the working directory's sector.
;
; Volatile registers:
; $a8-$a11
;
STORE_CWD:
    ASET 10
    OS_LOCALSYSCALL PATH_TOP
    ASET 10
    LARh FSBUF_DIRBUF
    ASET 11
    OS_SYSCALL FS_WRITE_SECTOR
    ASET 8
    OS_SYSCALL_RET


;
; Find the entry with a given name in FSBUF_DIRBUF.
; $a8 - The segment of the 6-byte (NUL padded) name
; $a9 - The segment local address of the name
;
; Returns:
; $a8 - Status: 0 if found, 2 (not found) otherwise
; $a9 - The offset of the entry in FSBUF_DIRBUF
;
; Volatile registers:
; $a8-$a15
;
FIND_ENTRY:
    ASET 15
    OS_SYSCALL OSUTIL_PUSHREGSANDCOPY   ; $a0:$a1 = name

    ASET 2         ; $a2 = entry offset
    AND 0
    FE_LP:
        LAh FSBUF_DIRBUF
        STal
        ASET 8
        LD
        BRzp FE_NEXT   ; Free slot

        ASET 0
        SPUSH
        ASET 8
        SPOP
        ASET 1
        SPUSH
        ASET 9
        SPOP
        ASET 10
        LARh FSBUF_DIRBUF
        ASET 2
        SPUSH
        ASET 11
        SPOP
        ADD 2
        ASET 12
        LARl 6
        ASET 13
        OS_SYSCALL MEMUTIL_MEMCMP
        ASET 13
        BRnp FE_FOUND

        FE_NEXT:
        ASET 2
        ADD 8
        BRnp FE_LP

    ASET 8
    LARl 2
    JMP FE_RET

    FE_FOUND:
    ASET 8
    AND 0

    FE_RET:
    ASET 2
    SPUSH
    ASET 9
    SPOP
    ASET 15
    OS_SYSCALL OSUTIL_POPREGS
    ASET 15
    OS_SYSCALL_RET


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

;
; Parse a name argument into a 6-byte, NUL padded buffer.
; A valid name is 1-6 characters in the range 0x21-0x7E, with no '/',
; and does not start with '.'. Neither string may cross a page.
; $a8  - The segment of the NUL terminated source string
; $a9  - The segment local address of the source string
; $a10 - The segment of the 6-byte destination buffer
; $a11 - The segment local address of the destination buffer
;
; Returns:
; $a8 - Status: 0 if valid, 4 (bad name) or 12 (missing argument)
;
; Volatile registers:
; $a8-$a14
;
PARSE_NAME:
    ASET 12
    LARl 0xFA      ; $a12 = -6 (character counter)

    ; The name must not be empty or start with '.'
    ASET 8
    STah
    ASET 9
    STal
    ASET 13
    LD
    BRz PN_MISSING
    SPUSH
    ASET 14
    LARl 0x2E
    SPOP XOR
    BRz PN_BAD

    PN_LP:
        ASET 8
        STah
        ASET 9
        STal
        ASET 13
        LD
        BRz PN_STORE   ; End of string: pad with NULs (source not advanced)
        BRn PN_BAD     ; >= 0x80

        ; Reject characters <= 0x20
        SPUSH
        ASET 14
        LARl 0xDF      ; -0x21
        SPOP ADD
        BRn PN_BAD

        ; Reject 0x7F
        ASET 13
        SPUSH
        ASET 14
        SPOP
        ADD 1
        BRn PN_BAD

        ; Reject '/'
        ASET 13
        SPUSH
        ASET 14
        LARl 0x2F
        SPOP XOR
        BRz PN_BAD

        ASET 9
        ADD 1

        PN_STORE:
        ASET 10
        STah
        ASET 11
        STal
        ADD 1
        ASET 13
        ST
        ASET 12
        ADD 1
        BRnp PN_LP

    ; The name must end after 6 characters
    ASET 8
    STah
    ASET 9
    STal
    ASET 13
    LD
    BRnp PN_BAD

    ASET 8
    AND 0
    JMP PN_RET

    PN_MISSING:
    ASET 8
    LARl 12
    JMP PN_RET

    PN_BAD:
    ASET 8
    LARl 4

    PN_RET:
    ASET 9
    OS_SYSCALL_RET


;
; Find a free entry in FSBUF_DIRBUF.
;
; Returns:
; $a8 - Status: 0 if found, 5 (directory full) otherwise
; $a9 - The offset of the free entry in FSBUF_DIRBUF
;
; Volatile registers:
; $a8-$a10
;
FIND_FREE_ENTRY:
    LAh FSBUF_DIRBUF
    ASET 9
    AND 0
    FF_LP:
        STal
        ASET 8
        LD
        BRzp FF_FOUND
        ASET 9
        ADD 8
        BRnp FF_LP

    ASET 8
    LARl 5
    JMP FF_RET

    FF_FOUND:
    ASET 8
    AND 0

    FF_RET:
    ASET 10
    OS_SYSCALL_RET


;
; Print the entries of FSBUF_DIRBUF, one per line. Directories are
; followed by '/', executable files by '*'.
;
; Volatile registers:
; $a8-$a13
;
LIST_DIR:
    ASET 9         ; $a9 = entry offset
    AND 0
    LD_LP:
        LAh FSBUF_DIRBUF
        STal
        ASET 10
        LD
        BRzp LD_NEXT
        SPUSH          ; Save the flags byte

        ; Print up to 6 name characters
        ASET 11
        LARl 0xFA
        ASET 9
        SPUSH
        ASET 12
        SPOP
        ADD 2
        LD_NAME:
            ASET 12
            STal
            ASET 13
            LD
            BRz LD_NAME_END
            PORTOUT_TTY_WRITE
            ASET 12
            ADD 1
            ASET 11
            ADD 1
            BRnp LD_NAME
        LD_NAME_END:

        ; Print the suffix
        ASET 10
        SPOP
        SPUSH
        SHFl 2         ; Bit 5 (file) -> bit 7
        BRn LD_ISFILE
        SPOP
        LARl 0x2F      ; '/'
        PORTOUT_TTY_WRITE
        JMP LD_NL
        LD_ISFILE:
        SPOP
        SHFl 1         ; Bit 6 (executable) -> bit 7
        BRzp LD_NL
        LARl 0x2A      ; '*'
        PORTOUT_TTY_WRITE
        LD_NL:
        LARl 0x0A
        PORTOUT_TTY_WRITE

        LD_NEXT:
        ASET 9
        ADD 8
        BRnp LD_LP

    ASET 10
    OS_SYSCALL_RET
