; asmsyntax=apricos
; ===================================
; ==                               ==
; ==  ApricotOS disk shell         ==
; ==  commands                     ==
; ==                               ==
; ==  DISKSEL and DISKSTAT.        ==
; ==                               ==
; ===================================
;
; Both commands are entered from the shell with $a8 = the segment local
; address of the argument string (in SHELLMEM_CMDBUFF's segment) and the
; shell's return address on the stack.
;

#name "diskcmds"
#segment 50

#include "apricotosint.asm"
#include "shellmem.asm"
#include "fsmem.asm"
#include "fsbuf.asm"
#include "fsdriver.asm"
#include "fscmds.asm"
#include "disp.asm"
#include "portin.asm"
#include "portout.asm"


;
; DISKSEL N: select disk N (0-8) and mount its filesystem, with the root
; as the working directory. If N.dsk doesn't exist, the current disk
; stays selected and the status is 13 (no such disk).
;
DISKSEL:
    ASET 8
    SPUSH
    ASET 9
    SPOP
    LAh SHELLMEM_CMDBUFF
    STal
    ASET 10
    LD             ; $a10 = first character
    BRz DS_MISSING
    ASET 9
    ADD 1
    STal
    ASET 11
    LD             ; $a11 = second character (must be the end)
    BRnp DS_BAD

    ; $a10 = N, which must be 0-8
    ASET 12
    LARl 0xD0      ; -'0'
    SPUSH
    ASET 10
    SPOP ADD
    BRn DS_BAD
    SPUSH
    ASET 12
    LARl 0xF7      ; -9
    SPOP ADD
    BRzp DS_BAD

    ; Select it, keeping the old disk number in $a11
    ASET 11
    PORTIN_DISK_STATUS
    ASET 10
    PORTOUT_DISK_SEL
    ASET 12
    PORTIN_DISK_STATUS
    SPUSH
    ASET 10
    SPOP XOR       ; Zero if disk N is now selected
    BRz DS_OK

    ; Not selected. An older simulator closes the current disk when a
    ; select fails: reselect the old disk if nothing is selected now.
    ASET 12
    NOT
    BRnp DS_BAD
    ASET 11
    PORTOUT_DISK_SEL

    DS_BAD:
    ASET 8
    LARl 13
    JMP DS_FINISH

    DS_MISSING:
    ASET 8
    LARl 12
    JMP DS_FINISH

    DS_OK:
    ASET 8
    OS_SYSCALL FS_INIT
    ASET 8
    OS_SYSCALL FS_NOTICE
    ASET 8
    AND 0

    DS_FINISH:
    ASET 9
    OS_SYSJUMP FSCMDS_FINISH


;
; Print a string from this segment.
; $a9 - The segment local address of the string
;
; Volatile registers:
; $a8-$a10
;
PS:
    ASET 8
    LARh S_DISK
    ASET 10
    OS_SYSCALL LIBDISP_PUTSTR
    ASET 8
    OS_SYSCALL_RET


S_DISK:    .stringz "DISK:      "
S_SIG:     .stringz "SIGNATURE: "
S_VOLUME:  .stringz "VOLUME:    "
S_BOOT:    .stringz "BOOTABLE:  "
S_VALID:   .stringz "VALID\n"
S_INVALID: .stringz "INVALID\n"
S_NONE:    .stringz "(NONE)\n"
S_YES:     .stringz "YES\n"
S_NO:      .stringz "NO\n"
S_NODISK:  .stringz "NO DISK\n"


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

;
; DISKSTAT: print the selected disk and its volume information:
; the disk number, whether the signature is valid, the volume name and
; whether the disk is bootable.
;
DISKSTAT:
    ASET 8
    PORTIN_DISK_STATUS
    NOT
    BRnp DT_HAVE_DISK
    ASET 9
    LARl S_NODISK
    ASET 10
    OS_SYSCALL PS
    JMP DT_RET

    DT_HAVE_DISK:
    ASET 9
    LARl S_DISK
    ASET 10
    OS_SYSCALL PS
    ASET 8
    PORTIN_DISK_STATUS
    SPUSH
    LARl 0x30
    SPOP ADD
    PORTOUT_TTY_WRITE
    LARl 0x0A
    PORTOUT_TTY_WRITE

    ; Signature (from the last mount)
    ASET 9
    LARl S_SIG
    ASET 10
    OS_SYSCALL PS
    LAh FSBUF_VOLSTATE
    LAl FSBUF_VOLSTATE
    ASET 8
    LD
    NOT
    ADD 1
    NOT            ; Zero if the state is 1 (no signature)
    BRnp DT_VALID
    ASET 9
    LARl S_INVALID
    ASET 10
    OS_SYSCALL PS
    JMP DT_RET

    DT_VALID:
    ASET 9
    LARl S_VALID
    ASET 10
    OS_SYSCALL PS

    ; Volume name: up to 8 characters at offset 4
    ASET 9
    LARl S_VOLUME
    ASET 10
    OS_SYSCALL PS
    LAh FSMEM_VOL_INFO
    LAl 4
    ASET 8
    LD
    BRnp DT_NAME
    ASET 9
    LARl S_NONE
    ASET 10
    OS_SYSCALL PS
    JMP DT_BOOT

    DT_NAME:
    ASET 9
    LARl 4         ; $a9 = offset
    ASET 10
    LARl 0xF8      ; $a10 = -8
    DT_NAME_LP:
        ASET 9
        STal
        ASET 8
        LD
        BRz DT_NAME_END
        PORTOUT_TTY_WRITE
        ASET 9
        ADD 1
        ASET 10
        ADD 1
        BRnp DT_NAME_LP
    DT_NAME_END:
    ASET 8
    LARl 0x0A
    PORTOUT_TTY_WRITE

    ; Bootable if bytes 254-255 are 0xAA 0x55
    DT_BOOT:
    ASET 9
    LARl S_BOOT
    ASET 10
    OS_SYSCALL PS
    ASET 9
    LARl S_NO
    LAh FSMEM_VOL_INFO
    LAl 254
    ASET 10
    LARl 0x56      ; -0xAA
    SPUSH
    ASET 8
    LD
    SPOP ADD
    BRnp DT_BOOT_PRINT
    LAl 255
    ASET 10
    LARl 0xAB      ; -0x55
    SPUSH
    ASET 8
    LD
    SPOP ADD
    BRnp DT_BOOT_PRINT
    ASET 9
    LARl S_YES
    DT_BOOT_PRINT:
    ASET 10
    OS_SYSCALL PS

    DT_RET:
    ASET 8
    OS_SYSCALL_RET
