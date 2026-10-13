; asmsyntax=apricos
; ===================================
; ==                               ==
; ==  ApricotOS Filesystem         ==
; ==  format (FORMAT)              ==
; ==                               ==
; ===================================
;

#name "fsformat"
#segment 47

#include "apricotosint.asm"
#include "memutil.asm"
#include "fsmem.asm"
#include "fsbuf.asm"
#include "fsdriver.asm"
#include "diskio.asm"
#include "diskalloc.asm"
#include "disp.asm"
#include "portin.asm"
#include "portout.asm"


;
; FORMAT: create an empty filesystem on the selected disk, after asking
; for confirmation. Only 'Y' or 'y' proceeds; any other key cancels.
; If the disk has no signature, the volume information sector is
; rewritten (signature, name, not bootable). Otherwise only its name is
; changed, and only if a name is given.
; $a8 - The segment of the argument string (optional volume name)
; $a9 - The segment local address of the argument string
;
; Returns:
; $a8 - Status: 0 (also when cancelled), 4 (bad name) or 13 (no disk)
;
; Volatile registers:
; $a8-$a15
;
FORMAT:
    ASET 10
    OS_SYSCALL PARSE_VOLNAME
    ASET 8
    BRnp FORMAT_RET

    PORTIN_DISK_STATUS
    NOT
    BRnp FORMAT_HAVE_DISK
    ASET 8
    LARl 13
    JMP FORMAT_RET

    FORMAT_HAVE_DISK:
    ASET 8
    OS_SYSCALL CONFIRM
    ASET 8
    BRz FORMAT_RET     ; Cancelled (status 0)

    ASET 8
    OS_SYSCALL PREP_VOLINFO

    ; Clear the bitmap, then mark track 0 and the root directory as allocated
    ASET 8
    LARh FSMEM_VOL_BITMAP
    ASET 9
    AND 0
    ASET 10
    OS_SYSCALL MEMUTIL_SEGSET

    ASET 8
    LARh FSMEM_VOL_BITMAP
    ASET 9
    AND 0
    ASET 10
    LARl 8
    ASET 11
    LARl 0xFF
    ASET 12
    OS_SYSCALL MEMUTIL_MEMSET

    LAh FSMEM_VOL_BITMAP
    LAl 8
    ASET 8
    AND 0
    ADD 1
    ST

    ; Write an empty root directory, then the bitmap, then the volume info
    ASET 8
    LARh FSBUF_DATABUF
    ASET 9
    AND 0
    ASET 10
    OS_SYSCALL MEMUTIL_SEGSET

    ASET 8
    AND 0
    ADD 1
    ASET 9
    AND 0
    ASET 10
    LARh FSBUF_DATABUF
    ASET 11
    OS_SYSCALL FS_WRITE_SECTOR

    ASET 8
    OS_SYSCALL DISKALLOC_FLUSH_BITMAP

    ASET 8
    OS_SYSCALL FLUSH_VOLINFO

    ; The disk is now mounted, with the root as the working directory
    ASET 8
    OS_SYSCALL FS_PATH_RESET

    LAh FSBUF_MOUNTED
    LAl FSBUF_MOUNTED
    ASET 8
    AND 0
    ADD 1
    ST
    LAl FSBUF_VOLSTATE
    AND 0
    ST

    FORMAT_RET:
    ASET 9
    OS_SYSCALL_RET


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

;
; Parse an optional volume name (up to 8 characters in 0x21-0x7E) into
; FSBUF_VOLNAME, NUL padded. An empty string leaves FSBUF_VOLNAME[0] = 0.
; $a8 - The segment of the string
; $a9 - The segment local address of the string
;
; Returns:
; $a8 - Status: 0 or 4 (bad name)
;
; Volatile registers:
; $a8-$a14
;
PARSE_VOLNAME:
    ASET 10
    LARl FSBUF_VOLNAME
    ASET 12
    LARl 0xF8          ; $a12 = -8 (character counter)
    PV_LP:
        ASET 8
        STah
        ASET 9
        STal
        ASET 13
        LD
        BRz PV_STORE   ; End of string: pad with NULs
        BRn PV_BAD
        SPUSH
        ASET 14
        LARl 0xDF      ; -0x21
        SPOP ADD
        BRn PV_BAD     ; <= 0x20
        ASET 13
        SPUSH
        ASET 14
        SPOP
        ADD 1
        BRn PV_BAD     ; 0x7F
        ASET 9
        ADD 1

        PV_STORE:
        LAh FSBUF_VOLNAME
        ASET 10
        STal
        ADD 1
        ASET 13
        ST
        ASET 12
        ADD 1
        BRnp PV_LP

    ; The name must end after 8 characters
    ASET 8
    STah
    ASET 9
    STal
    ASET 13
    LD
    BRnp PV_BAD
    ASET 8
    AND 0
    JMP PV_RET

    PV_BAD:
    ASET 8
    LARl 4

    PV_RET:
    ASET 9
    OS_SYSCALL_RET


;
; Ask "FORMAT DISK n? (Y/N) " and read one key.
;
; Returns:
; $a8 - Non-zero to go ahead, zero if cancelled
;
; Volatile registers:
; $a8-$a10
;
CONFIRM:
    ASET 9
    LARl S_ASK
    ASET 10
    OS_SYSCALL PS
    ASET 8
    PORTIN_DISK_STATUS
    SPUSH
    LARl 0x30
    SPOP ADD
    PORTOUT_TTY_WRITE
    ASET 9
    LARl S_YN
    ASET 10
    OS_SYSCALL PS

    ASET 9
    PORTIN_KBD_INPUT
    SPUSH
    ASET 10            ; Echo printable keys (0x20-0x7E)
    LARl 0xE0
    SPOP ADD           ; $a10 = key - 0x20
    BRn CF_NOECHO
    SPUSH
    LARl 0xA1
    SPOP ADD           ; Negative only for key - 0x20 in 0x00-0x5E
    BRzp CF_NOECHO
    ASET 9
    PORTOUT_TTY_WRITE
    CF_NOECHO:
    ASET 8
    LARl 0x0A
    PORTOUT_TTY_WRITE

    ; 'Y' (0x59) or 'y' (0x79)
    ASET 8
    LARl 0xDF
    SPUSH
    ASET 9
    SPOP AND           ; Clear the lowercase bit
    SPUSH
    ASET 8
    LARl 0xA7          ; -0x59
    SPOP ADD
    BRz CF_YES

    ASET 9
    LARl S_CANCEL
    ASET 10
    OS_SYSCALL PS
    ASET 8
    AND 0
    JMP CF_RET

    CF_YES:
    ASET 8
    OR 1

    CF_RET:
    ASET 9
    OS_SYSCALL_RET


;
; Prepare FSMEM_VOL_INFO for FORMAT. With no valid signature the sector
; is cleared and given the signature and a name (FSBUF_VOLNAME, or
; APRICOT). Otherwise the name is replaced only if FSBUF_VOLNAME is set.
;
; Volatile registers:
; $a8-$a13
;
PREP_VOLINFO:
    LAh FSBUF_VOLSTATE
    LAl FSBUF_VOLSTATE
    ASET 8
    LD
    NOT
    ADD 1
    NOT                ; Zero if the state is 1 (no signature)
    BRnp PVI_NAME

    ASET 8
    LARh FSMEM_VOL_INFO
    ASET 9
    AND 0
    ASET 10
    OS_SYSCALL MEMUTIL_SEGSET
    ASET 8             ; Signature and default name
    LARh SIG_AND_NAME
    ASET 9
    LARl SIG_AND_NAME
    ASET 10
    LARh FSMEM_VOL_INFO
    ASET 11
    AND 0
    ASET 12
    LARl 12
    ASET 13
    OS_SYSCALL MEMUTIL_MEMCPY

    PVI_NAME:
    LAh FSBUF_VOLNAME
    LAl FSBUF_VOLNAME
    ASET 8
    LD
    BRz PVI_RET
    LARh FSBUF_VOLNAME
    ASET 9
    LARl FSBUF_VOLNAME
    ASET 10
    LARh FSMEM_VOL_INFO
    ASET 11
    AND 0
    ADD 4
    ASET 12
    LARl 8
    ASET 13
    OS_SYSCALL MEMUTIL_MEMCPY

    PVI_RET:
    ASET 8
    OS_SYSCALL_RET


;
; Write FSMEM_VOL_INFO to track 0, sector 62.
;
; Volatile registers:
; $a8-$a11
;
FLUSH_VOLINFO:
    ASET 8
    DISKIO_TRACKSEL 0
    LARh FSMEM_VOL_INFO
    ASET 9
    LARl 62
    ASET 10
    OS_SYSCALL DISKIO_COPYTODSK
    ASET 10
    OS_SYSCALL_RET


;
; Print a string from this segment.
; $a9 - The segment local address of the string
;
; Volatile registers:
; $a8-$a10
;
PS:
    ASET 8
    LARh S_ASK
    ASET 10
    OS_SYSCALL LIBDISP_PUTSTR
    ASET 8
    OS_SYSCALL_RET


SIG_AND_NAME:
.fill 0xC0
.fill 0x30
.fill 0x0C
.fill 0x03
.stringz 'APRICOT'
.fill 0

S_ASK:    .stringz "FORMAT DISK "
S_YN:     .stringz "? (Y/N) "
S_CANCEL: .stringz "CANCELLED\n"
