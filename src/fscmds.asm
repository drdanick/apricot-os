; asmsyntax=apricos
; ===================================
; ==                               ==
; ==  ApricotOS Filesystem shell   ==
; ==          commands             ==
; ==                               ==
; ==  Shell command handlers for   ==
; ==  the filesystem commands.     ==
; ==                               ==
; ===================================
;
; Handlers are entered from the shell (see shell.asm EXECUTE_COMMAND) with:
; $a8 - The segment local address of the argument string (its segment is
;       that of SHELLMEM_CMDBUFF)
; and the shell's return address on the stack.
;
; Segment 27: handlers, RUN_FS, FINISH, LIST, PRINT_ERROR
; Segment 28: error table and messages
;

#name "fscmds"
#segment 27

#include "apricotosint.asm"
#include "shellmem.asm"
#include "disp.asm"
#include "fsbuf.asm"
#include "fsdriver.asm"
#include "fsdir.asm"
#include "fspath.asm"
#include "fsread.asm"
#include "fswrite.asm"
#include "fsdel.asm"
#include "fscopy.asm"
#include "fsformat.asm"
#include "fsinfo.asm"


;=========================================
;==         COMMAND HANDLERS            ==
;=========================================
;
; Each handler loads the address of the routine implementing the command
; into $a10:$a11 and jumps to RUN_FS. Those routines take:
; $a8 - The segment of the argument string
; $a9 - The segment local address of the argument string
; and return a status code in $a8.
;

LS:
    ASET 10
    LARh LIST
    ASET 11
    LARl LIST
    JMP RUN_FS

CD:
    ASET 10
    LARh FSPATH_CHDIR
    ASET 11
    LARl FSPATH_CHDIR
    JMP RUN_FS

PWD:
    ASET 10
    LARh FSPATH_PRINT_PATH
    ASET 11
    LARl FSPATH_PRINT_PATH
    JMP RUN_FS

CAT:
    ASET 10
    LARh FSREAD_CAT
    ASET 11
    LARl FSREAD_CAT
    JMP RUN_FS

TOUCH:
    ASET 10
    LARh FSWRITE_TOUCH
    ASET 11
    LARl FSWRITE_TOUCH
    JMP RUN_FS

MKDIR:
    ASET 10
    LARh FSWRITE_MKDIR
    ASET 11
    LARl FSWRITE_MKDIR
    JMP RUN_FS

WRITE:
    ASET 10
    LARh FSWRITE_WRITE
    ASET 11
    LARl FSWRITE_WRITE
    JMP RUN_FS

RM:
    ASET 10
    LARh FSDEL_REMOVE
    ASET 11
    LARl FSDEL_REMOVE
    JMP RUN_FS

MV:
    ASET 10
    LARh FSDEL_RENAME
    ASET 11
    LARl FSDEL_RENAME
    JMP RUN_FS

CP:
    ASET 10
    LARh FSCOPY_COPY
    ASET 11
    LARl FSCOPY_COPY
    JMP RUN_FS

STAT:
    ASET 10
    LARh FSINFO_STAT
    ASET 11
    LARl FSINFO_STAT
    JMP RUN_FS

; FORMAT works without a mounted filesystem, so it skips RUN_FS
FORMAT:
    ASET 8
    SPUSH
    ASET 9
    SPOP
    ASET 8
    LARh SHELLMEM_CMDBUFF
    ASET 10
    OS_SYSCALL FSFORMAT_FORMAT
    JMP FINISH


;
; Run a filesystem command routine.
; $a8  - The segment local address of the argument string
; $a10 - The segment of the routine
; $a11 - The segment local address of the routine
;
; Never returns to its caller: it ends in FINISH, which returns to the shell.
;
RUN_FS:
    ASET 8
    SPUSH
    ASET 9
    SPOP           ; $a9 = argument string (local address)

    LAh FSBUF_MOUNTED
    LAl FSBUF_MOUNTED
    ASET 8
    LD
    BRz NOT_MOUNTED
    LARh SHELLMEM_CMDBUFF

    ; Call $a10:$a11: OS_SYSCALL expanded by hand, since the target is in
    ; registers rather than a label
    ASET 12
    LDI RUN_FS_RET
    LDah
    SPUSH
    LDal
    SPUSH
    ASET 10
    STah
    ASET 11
    STal
    JMP
    RUN_FS_RET:
    JMP FINISH

; Status 1: no filesystem
NOT_MOUNTED:
    ASET 8
    AND 0
    ADD 1
    ; Falls through into FINISH

;
; Common handler exit: print an error message if the status is
; non-zero, then return to the shell.
; $a8 - The status code
;
; Shell handlers outside this unit (DISKSEL, FSSTAT) reach it with
; OS_SYSJUMP FSCMDS_FINISH.
;
FINISH:
    ASET 8
    BRz FINISH_RET
    ASET 9
    OS_SYSCALL PRINT_ERROR
    FINISH_RET:
    ASET 8
    OS_SYSCALL_RET


;=========================================
;==        COMMAND ROUTINES             ==
;=========================================

;
; LS: list the working directory.
;
; Returns:
; $a8 - Status (always 0)
;
LIST:
    ASET 8
    OS_SYSCALL FSDIR_LOAD_CWD
    ASET 8
    OS_SYSCALL FSDIR_LIST_DIR
    ASET 8
    AND 0
    ASET 9
    OS_SYSCALL_RET



;
; Print "ERROR: <message>" for a status code.
; $a8 - The status code (1-13)
;
; Volatile registers:
; $a8-$a10
;
PRINT_ERROR:
    ASET 8
    SPUSH
    LARh ERR_PREFIX
    ASET 9
    LARl ERR_PREFIX
    ASET 10
    OS_SYSCALL LIBDISP_PUTSTR

    ; Look up ERR_TABLE[status] (entry 0, the prefix, is never used)
    ASET 9
    LARl ERR_TABLE
    SPOP ADD
    STal
    LAh ERR_TABLE
    LD             ; $a9 = low byte of the message address
    ASET 8
    LARh ERR_TABLE
    ASET 10
    OS_SYSCALL LIBDISP_PUTSTR

    ASET 8
    OS_SYSCALL_RET


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

; Error messages, indexed by status code. The table and the strings must
; stay in one segment (PRINT_ERROR only sets the low byte of the address).
ERR_TABLE:
.nearptr ERR_PREFIX
.nearptr ERR_1
.nearptr ERR_2
.nearptr ERR_3
.nearptr ERR_4
.nearptr ERR_5
.nearptr ERR_6
.nearptr ERR_7
.nearptr ERR_8
.nearptr ERR_9
.nearptr ERR_10
.nearptr ERR_11
.nearptr ERR_12
.nearptr ERR_13

ERR_PREFIX: .stringz "ERROR: "
ERR_1:  .stringz "NO FILESYSTEM\n"
ERR_2:  .stringz "NOT FOUND\n"
ERR_3:  .stringz "ALREADY EXISTS\n"
ERR_4:  .stringz "BAD NAME\n"
ERR_5:  .stringz "DIRECTORY FULL\n"
ERR_6:  .stringz "DISK FULL\n"
ERR_7:  .stringz "FILE TOO BIG\n"
ERR_8:  .stringz "NOT A DIRECTORY\n"
ERR_9:  .stringz "NOT A FILE\n"
ERR_10: .stringz "DIRECTORY NOT EMPTY\n"
ERR_11: .stringz "PATH TOO DEEP\n"
ERR_12: .stringz "MISSING ARGUMENT\n"
ERR_13: .stringz "NO SUCH DISK\n"
