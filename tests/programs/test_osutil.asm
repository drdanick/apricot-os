; asmsyntax=apricos
;
; osutil tests (run with MEMEXEC 4F00). Uses scratch RAM at 0x7300.
;
; Output lines (bytes in hex):
;   PUSHREGS a0..a7                 after PUSHREGS, clobbering, POPREGS
;   PUSHVOLATILEREGS a8..a14        after PUSHVOLATILEREGS, clobbering, POPVOLATILEREGS
;   PUSHALLREGS a0..a7 a8..a14      after PUSHALLREGS, clobbering, POPALLREGS
;   PUSHREGSANDCOPY a0..a6          a0-a6 just after PUSHREGSANDCOPY (copies of a8-a14)
;   RESTORED a0..a7                 after the matching POPREGS
;
; ($a15 is the scratch register of every call, so it is never checked.)
;

#segment 0x4F
#name "test_osutil"

#include "apricotos.asm"
#include "osutil.asm"
#include "disp.asm"
#include "testlib.asm"
#include "testmacros.asm"


    ; PUSHREGS / POPREGS
    TM_SET 0 0x10
    TM_SET 1 0x11
    TM_SET 2 0x12
    TM_SET 3 0x13
    TM_SET 4 0x14
    TM_SET 5 0x15
    TM_SET 6 0x16
    TM_SET 7 0x17
    OS_CALLFUNC OSUTIL_PUSHREGS
    OS_CALLFUNC CLOBBER_ALL
    OS_CALLFUNC OSUTIL_POPREGS
    TM_LABEL T_PUSHREGS
    OS_CALLFUNC PRINT_LOW
    TM_NL

    ; PUSHVOLATILEREGS / POPVOLATILEREGS
    TM_SET 8 0x28
    TM_SET 9 0x29
    TM_SET 10 0x2A
    TM_SET 11 0x2B
    TM_SET 12 0x2C
    TM_SET 13 0x2D
    TM_SET 14 0x2E
    OS_CALLFUNC OSUTIL_PUSHVOLATILEREGS
    OS_CALLFUNC CLOBBER_ALL
    OS_CALLFUNC OSUTIL_POPVOLATILEREGS
    OS_CALLFUNC SAVE_HIGH
    TM_LABEL T_PUSHVOLATILE
    OS_CALLFUNC PRINT_HIGH
    TM_NL

    ; PUSHALLREGS / POPALLREGS
    TM_SET 0 0x30
    TM_SET 1 0x31
    TM_SET 2 0x32
    TM_SET 3 0x33
    TM_SET 4 0x34
    TM_SET 5 0x35
    TM_SET 6 0x36
    TM_SET 7 0x37
    TM_SET 8 0x38
    TM_SET 9 0x39
    TM_SET 10 0x3A
    TM_SET 11 0x3B
    TM_SET 12 0x3C
    TM_SET 13 0x3D
    TM_SET 14 0x3E
    OS_CALLFUNC OSUTIL_PUSHALLREGS
    OS_CALLFUNC CLOBBER_ALL
    OS_CALLFUNC OSUTIL_POPALLREGS
    OS_CALLFUNC SAVE_HIGH
    TM_LABEL T_PUSHALL
    OS_CALLFUNC PRINT_LOW
    OS_CALLFUNC PRINT_HIGH
    TM_NL

    OS_CALLFUNC COPY_TEST
    OS_PROG_EXIT


; Set $a0-$a14 to 0xEE.
CLOBBER_ALL:
    TM_SET 0 0xEE
    TM_SET 1 0xEE
    TM_SET 2 0xEE
    TM_SET 3 0xEE
    TM_SET 4 0xEE
    TM_SET 5 0xEE
    TM_SET 6 0xEE
    TM_SET 7 0xEE
    TM_SET 8 0xEE
    TM_SET 9 0xEE
    TM_SET 10 0xEE
    TM_SET 11 0xEE
    TM_SET 12 0xEE
    TM_SET 13 0xEE
    TM_SET 14 0xEE
    OS_FUNC_RETURN

T_PUSHREGS:     .stringz "PUSHREGS "
T_PUSHVOLATILE: .stringz "PUSHVOLATILEREGS "
T_PUSHALL:      .stringz "PUSHALLREGS "
T_COPY:         .stringz "PUSHREGSANDCOPY "
T_RESTORED:     .stringz "RESTORED "


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

; Save $a8-$a14 to 0x7300-0x7306 (printing would clobber them).
SAVE_HIGH:
    TM_STORE 8 0x73 0x00
    TM_STORE 9 0x73 0x01
    TM_STORE 10 0x73 0x02
    TM_STORE 11 0x73 0x03
    TM_STORE 12 0x73 0x04
    TM_STORE 13 0x73 0x05
    TM_STORE 14 0x73 0x06
    OS_FUNC_RETURN

; Print the saved $a8-$a14.
PRINT_HIGH:
    TM_PMEM 0x73 0x00
    TM_PMEM 0x73 0x01
    TM_PMEM 0x73 0x02
    TM_PMEM 0x73 0x03
    TM_PMEM 0x73 0x04
    TM_PMEM 0x73 0x05
    TM_PMEM 0x73 0x06
    OS_FUNC_RETURN

; Print $a0-$a7.
PRINT_LOW:
    TM_PREG 0
    TM_PREG 1
    TM_PREG 2
    TM_PREG 3
    TM_PREG 4
    TM_PREG 5
    TM_PREG 6
    TM_PREG 7
    OS_FUNC_RETURN


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

; PUSHREGSANDCOPY then POPREGS
COPY_TEST:
    TM_SET 0 0x40
    TM_SET 1 0x41
    TM_SET 2 0x42
    TM_SET 3 0x43
    TM_SET 4 0x44
    TM_SET 5 0x45
    TM_SET 6 0x46
    TM_SET 7 0x47
    TM_SET 8 0x58
    TM_SET 9 0x59
    TM_SET 10 0x5A
    TM_SET 11 0x5B
    TM_SET 12 0x5C
    TM_SET 13 0x5D
    TM_SET 14 0x5E
    OS_CALLFUNC OSUTIL_PUSHREGSANDCOPY
    ; The stack now holds the saved $a0-$a7 until POPREGS below
    TM_LABEL T_COPY
    TM_PREG 0
    TM_PREG 1
    TM_PREG 2
    TM_PREG 3
    TM_PREG 4
    TM_PREG 5
    TM_PREG 6
    TM_NL
    OS_CALLFUNC OSUTIL_POPREGS
    TM_LABEL T_RESTORED
    OS_CALLFUNC PRINT_LOW
    TM_NL
    OS_FUNC_RETURN
