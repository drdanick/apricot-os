; asmsyntax=apricos
; ===================================
; ==                               ==
; ==  ApricotOS Filesystem         ==
; ==  working directory routines   ==
; ==                               ==
; ==  Maintains the path stack     ==
; ==  (CD and PWD).                ==
; ==                               ==
; ===================================
;
; The path stack (FSBUF_PATH_STACK) holds up to 16 8-byte entries, each a
; copy of the directory entry of one directory on the current path.
; Entry 0 is the root. FSBUF_PATH_DEPTH is the number of entries in use,
; so the working directory is entry PATH_DEPTH-1.
;

#name "fspath"
#segment 23

#include "apricotosint.asm"
#include "memutil.asm"
#include "fsbuf.asm"
#include "fsdriver.asm"
#include "fsdir.asm"
#include "portout.asm"


;
; Push a directory entry of FSBUF_DIRBUF onto the path stack, making it
; the working directory.
; $a9 - The offset of the entry in FSBUF_DIRBUF
;
; Returns:
; $a8 - Status: 0 if successful, 11 (path too deep) otherwise
;
; Volatile registers:
; $a8-$a13
;
PATH_PUSH:
    LAh FSBUF_PATH_DEPTH
    LAl FSBUF_PATH_DEPTH
    ASET 10
    LD
    SPUSH
    SHFr 4             ; Non-zero if the stack already holds 16 entries
    BRnp PP_FULL

    SPOP
    SPUSH
    ADD 1
    ST                 ; PATH_DEPTH += 1
    SPOP               ; $a10 = index of the new entry
    SHFl 3
    SPUSH
    LARl FSBUF_PATH_STACK
    SPOP ADD
    SPUSH
    ASET 11
    SPOP               ; $a11 = destination (local address)
    ASET 10
    LARh FSBUF_PATH_STACK
    ASET 8
    LARh FSBUF_DIRBUF  ; $a8:$a9 = source entry
    ASET 12
    LARl 8
    ASET 13
    OS_SYSCALL MEMUTIL_MEMCPY

    ASET 8
    AND 0
    JMP PP_RET

    PP_FULL:
    SPOP
    ASET 8
    LARl 11

    PP_RET:
    ASET 9
    OS_SYSCALL_RET


;
; Pop the working directory off the path stack (CD ..).
; Does nothing at the root.
;
; Volatile registers:
; $a8
;
PATH_POP:
    LAh FSBUF_PATH_DEPTH
    LAl FSBUF_PATH_DEPTH
    ASET 8
    LD
    NOT
    ADD 1
    NOT
    BRz PATH_POP_RET
    ST
    PATH_POP_RET:
    OS_SYSCALL_RET


;
; Change the working directory.
; $a8 - The segment of the argument string
; $a9 - The segment local address of the argument string
;       ("/" = root, ".." = parent, otherwise a directory name)
;
; Returns:
; $a8 - Status code
;
; Volatile registers:
; $a8-$a15
;
CHDIR:
    ASET 8
    SPUSH
    ASET 9
    SPUSH              ; Save the argument address

    ; Load the first three characters into $a10, $a11, $a12
    ASET 8
    STah
    ASET 9
    STal
    ASET 10
    LD
    ASET 9
    ADD 1
    STal
    ASET 11
    LD
    ASET 9
    ADD 1
    STal
    ASET 12
    LD

    ; "/" ?
    ASET 11
    SPUSH
    ASET 10
    SPUSH
    ASET 13
    LARl 0x2F
    SPOP XOR
    SPOP OR
    BRz CD_ROOT

    ; ".." ?
    ASET 12
    SPUSH
    ASET 11
    SPUSH
    ASET 13
    LARl 0x2E
    SPOP XOR
    SPOP OR
    SPUSH
    ASET 10
    SPUSH
    ASET 13
    LARl 0x2E
    SPOP XOR
    SPOP OR
    BRz CD_UP

    ; A directory name
    ASET 9
    SPOP
    ASET 8
    SPOP
    ASET 10
    LARh FSBUF_NAMEBUF
    ASET 11
    LARl FSBUF_NAMEBUF
    ASET 12
    OS_SYSCALL FSDIR_PARSE_NAME
    ASET 8
    BRnp CD_RET

    OS_SYSCALL FSDIR_LOAD_CWD
    ASET 8
    LARh FSBUF_NAMEBUF
    ASET 9
    LARl FSBUF_NAMEBUF
    ASET 10
    OS_SYSCALL FSDIR_FIND_ENTRY
    ASET 8
    BRnp CD_RET

    ; It must be a directory (bit 5 clear)
    LAh FSBUF_DIRBUF
    ASET 9
    STal
    ASET 10
    LD
    SHFl 2
    BRn CD_NOTDIR

    ASET 10
    OS_SYSCALL PATH_PUSH
    JMP CD_RET

    CD_NOTDIR:
    ASET 8
    LARl 8
    JMP CD_RET

    CD_ROOT:
    SPOP
    SPOP
    ASET 8
    OS_SYSCALL FS_PATH_RESET
    JMP CD_OK

    CD_UP:
    SPOP
    SPOP
    ASET 8
    OS_SYSCALL PATH_POP

    CD_OK:
    ASET 8
    AND 0

    CD_RET:
    ASET 9
    OS_SYSCALL_RET


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

;
; Print the working directory's path ("/" or "/A/B"), then a newline.
; Can be called as a command routine (it ignores its arguments).
;
; Returns:
; $a8 - Status (always 0)
;
; Volatile registers:
; $a8-$a13
;
PRINT_PATH:
    LAh FSBUF_PATH_DEPTH
    LAl FSBUF_PATH_DEPTH
    ASET 11
    LD
    NOT
    ADD 1
    NOT                ; $a11 = number of path components
    BRnp PRP_HAVE
    ASET 10
    LARl 0x2F
    PORTOUT_TTY_WRITE
    JMP PRP_END

    PRP_HAVE:
    NOT
    ADD 1              ; $a11 = -(number of components)
    ASET 9
    LARl FSBUF_PATH_STACK
    ADD 8              ; $a9 = first component's entry
    LAh FSBUF_PATH_STACK
    PRP_LP:
        ASET 10
        LARl 0x2F
        PORTOUT_TTY_WRITE

        ASET 12
        LARl 0xFA
        ASET 9
        SPUSH
        ASET 13
        SPOP
        ADD 2          ; $a13 = name
        PRP_NAME:
            ASET 13
            STal
            ASET 10
            LD
            BRz PRP_NAME_END
            PORTOUT_TTY_WRITE
            ASET 13
            ADD 1
            ASET 12
            ADD 1
            BRnp PRP_NAME
        PRP_NAME_END:

        ASET 9
        ADD 8
        ASET 11
        ADD 1
        BRnp PRP_LP

    PRP_END:
    ASET 10
    LARl 0x0A
    PORTOUT_TTY_WRITE

    ASET 8
    AND 0
    ASET 9
    OS_SYSCALL_RET
