; asmsyntax=apricos
; ===================================
; ==                               ==
; ==  ApricotOS Filesystem         ==
; ==  statistics (FSSTAT)          ==
; ==                               ==
; ===================================
;

#name "fsstat"
#segment 45

#include "apricotosint.asm"
#include "fsmem.asm"
#include "fsbuf.asm"
#include "disp.asm"
#include "portin.asm"


;
; FSSTAT shell command: print the filesystem status and the used, free
; and total space of tracks 1-31 (1984 sectors).
; Entered from the shell (the argument is ignored); returns to the shell.
;
FSSTAT:
    ASET 9
    LARl S_FS
    ASET 10
    OS_SYSCALL PS

    ASET 8
    PORTIN_DISK_STATUS
    NOT
    BRnp FSSTAT_HAVE_DISK
    ASET 9
    LARl S_NODISK
    JMP FSSTAT_STATE

    FSSTAT_HAVE_DISK:
    LAh FSBUF_VOLSTATE
    LAl FSBUF_VOLSTATE
    ASET 8
    LD
    BRz FSSTAT_OK
    ASET 9
    LARl S_NOTFMT
    ASET 8
    NOT
    ADD 1
    NOT            ; Zero if the state is 1 (no signature)
    BRnp FSSTAT_STATE
    ASET 9
    LARl S_NOSIG

    FSSTAT_STATE:
    ASET 10
    OS_SYSCALL PS
    JMP FSSTAT_RET

    FSSTAT_OK:
    ASET 9
    LARl S_OK
    ASET 10
    OS_SYSCALL PS

    ; Used sectors
    ASET 10
    OS_SYSCALL COUNT_USED
    ASET 8
    SPUSH
    ASET 9
    SPUSH          ; Keep the count on the stack
    ASET 9
    LARl S_USED
    ASET 10
    OS_SYSCALL PS
    ASET 9
    SPOP
    ASET 8
    SPOP
    SPUSH
    ASET 9
    SPUSH
    ASET 10
    OS_SYSCALL PRINT_SECTORS

    ; Free sectors = 1984 - used = ~used + 0x07C1
    ASET 9
    LARl S_FREE
    ASET 10
    OS_SYSCALL PS
    ASET 9
    SPOP
    NOT
    SPUSH
    ASET 10
    LARl 0xC1
    SPOP ADD       ; Low byte, O = carry
    SPUSH
    PRTin 4
    SHFr 3         ; $a10 = carry
    ASET 9
    SPOP           ; $a9 = low byte
    ASET 8
    SPOP           ; $a8 = used (high byte)
    NOT
    ADD 7
    ASET 10
    SPUSH
    ASET 8
    SPOP ADD       ; $a8 = ~high + 7 + carry
    ASET 10
    OS_SYSCALL PRINT_SECTORS

    ; Total
    ASET 9
    LARl S_TOTAL
    ASET 10
    OS_SYSCALL PS
    ASET 8
    LARl 0x07
    ASET 9
    LARl 0xC0
    ASET 10
    OS_SYSCALL PRINT_SECTORS

    FSSTAT_RET:
    ASET 8
    OS_SYSCALL_RET


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

;
; Count the allocated sectors of tracks 1-31 (bitmap bytes 8-255).
;
; Returns:
; $a8 - The count (high byte)
; $a9 - The count (low byte)
;
; Volatile registers:
; $a8-$a11
;
COUNT_USED:
    ASET 8
    AND 0
    ASET 9
    AND 0
    ASET 11
    LARl 8
    LAh FSMEM_VOL_BITMAP
    CU_BYTE:
        ASET 11
        STal
        ASET 10
        LD
        CU_BIT:
            BRz CU_NEXT    ; No more allocated sectors in this byte
            BRzp CU_SHIFT  ; Bit 7 is clear
            ASET 9
            ADD 1
            BRnp CU_SHIFT
            ASET 8
            ADD 1
            CU_SHIFT:
            ASET 10
            SHFl 1
            JMP CU_BIT
        CU_NEXT:
        ASET 11
        ADD 1
        BRnp CU_BYTE

    ASET 10
    OS_SYSCALL_RET


;
; Print "<n> SECTORS (<n/4> KB)" and a newline.
; $a8 - The number of sectors (high byte)
; $a9 - The number of sectors (low byte)
;
; Volatile registers:
; $a8-$a15
;
PRINT_SECTORS:
    ASET 8
    SPUSH
    ASET 9
    SPUSH
    ASET 10
    OS_SYSCALL LIBDISP_PUTNUM16
    ASET 9
    LARl S_SECTORS
    ASET 10
    OS_SYSCALL PS

    ; KB = sectors / 4
    ASET 9
    SPOP
    ASET 8
    SPOP
    SPUSH
    ASET 10
    SPOP
    SHFl 6         ; $a10 = high << 6
    SPUSH
    ASET 9
    SHFr 2
    SPOP OR        ; $a9 = (low >> 2) | (high << 6)
    ASET 8
    SHFr 2
    ASET 10
    OS_SYSCALL LIBDISP_PUTNUM16
    ASET 9
    LARl S_KB
    ASET 10
    OS_SYSCALL PS

    ASET 8
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
    LARh S_FS
    ASET 10
    OS_SYSCALL LIBDISP_PUTSTR
    ASET 8
    OS_SYSCALL_RET


S_FS:      .stringz "FILESYSTEM: "
S_OK:      .stringz "OK\n"
S_NOSIG:   .stringz "NO SIGNATURE\n"
S_NOTFMT:  .stringz "NOT FORMATTED\n"
S_NODISK:  .stringz "NO DISK\n"
S_USED:    .stringz "USED:       "
S_FREE:    .stringz "FREE:       "
S_TOTAL:   .stringz "TOTAL:      "
S_SECTORS: .stringz " SECTORS ("
S_KB:      .stringz " KB)\n"
