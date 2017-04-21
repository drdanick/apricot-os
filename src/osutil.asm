; asmsyntax=apricos
; ===================================
; ==                               ==
; ==   ApricotOS utility routines  ==
; ==                               ==
; ==          Revision 1           ==
; ==                               ==
; == (C) 2014-17 Nick Stones-Havas ==
; ==                               ==
; ==                               ==
; ==  Provides a collection of     ==
; ==  OS utility routines.         ==
; ==                               ==
; ===================================
;
#name "osutil"
#segment 4

#include "apricotosint.asm"
#include "portout.asm"

; Function pointers
.nearptr PUSHREGS
.nearptr PUSHVOLATILEREGS
.nearptr PUSHALLREGS
.nearptr PUSHREGSANDCOPY
.nearptr POPREGS
.nearptr POPVOLATILEREGS
.nearptr POPALLREGS
.nearptr HALT


;
; Pushes all non-volatile registers ($a0-$a7) 
; to the stack. 
;
; Volatile registers:
; - Currently selected register
;
PUSHREGS:
    ; Place the return address in $mr before pushing anything to the stack
    OS_SYSCALL_RET_PREP

    ASET 0
    SPUSH
    ASET 1
    SPUSH
    ASET 2
    SPUSH
    ASET 3
    SPUSH
    ASET 4
    SPUSH
    ASET 5
    SPUSH
    ASET 6
    SPUSH
    ASET 7
    SPUSH

    JMP

;
; Pushes all volatile registers ($a8-$a15) 
; to the stack. 
;
; Volatile registers:
; - Currently selected register
;
PUSHVOLATILEREGS:
    ; Place the return address in $mr before pushing anything to the stack
    OS_SYSCALL_RET_PREP

    ASET 8
    SPUSH
    ASET 9
    SPUSH
    ASET 10
    SPUSH
    ASET 11
    SPUSH
    ASET 12
    SPUSH
    ASET 13
    SPUSH
    ASET 14
    SPUSH
    ASET 15
    SPUSH

    JMP

;
; Pushes all registers ($a0-$a15), except for the currently selected register, which is lost.
; to the stack.
;
; Volatile registers:
; - Currently selected register
;
PUSHALLREGS:
    ; Place the return address in $mr before pushing anything to the stack
    OS_SYSCALL_RET_PREP

    ASET 0
    SPUSH
    ASET 1
    SPUSH
    ASET 2
    SPUSH
    ASET 3
    SPUSH
    ASET 4
    SPUSH
    ASET 5
    SPUSH
    ASET 6
    SPUSH
    ASET 7
    SPUSH
    ASET 8
    SPUSH
    ASET 9
    SPUSH
    ASET 10
    SPUSH
    ASET 11
    SPUSH
    ASET 12
    SPUSH
    ASET 13
    SPUSH
    ASET 14
    SPUSH
    ASET 15
    SPUSH

    JMP
    

;
; Pushes all non-volatile registers ($a0-$a7) 
; to the stack and copies all volatile registers 
; ($a8-$a15) to $a0-$17.
;
; Volatile registers:
; - Currently selected register
;
PUSHREGSANDCOPY:
    ; Place the return address in $mr before pushing anything to the stack
    OS_SYSCALL_RET_PREP

    ; Cannot reuse this code from PUSHREGS due to the way it modifies the stack (return value will be lost)
    ASET 0
    SPUSH
    ASET 1
    SPUSH
    ASET 2
    SPUSH
    ASET 3
    SPUSH
    ASET 4
    SPUSH
    ASET 5
    SPUSH
    ASET 6
    SPUSH
    ASET 7
    SPUSH

    ; Copy the tempory registers to their corresponding non-temporary registers
    ASET 8
    SPUSH
    ASET 0
    SPOP
    ASET 9
    SPUSH
    ASET 1
    SPOP
    ASET 10
    SPUSH
    ASET 2
    SPOP
    ASET 11
    SPUSH
    ASET 3
    SPOP
    ASET 12
    SPUSH
    ASET 4
    SPOP
    ASET 13
    SPUSH
    ASET 5
    SPOP
    ASET 14
    SPUSH
    ASET 6
    SPOP
    ASET 15
    SPUSH
    ASET 7
    SPOP
        
    JMP

;
; Pops registers $a0-$a7 from the stack
;
; Volatile registers:
; - Currently selected register
;
POPREGS:
    OS_SYSCALL_RET_PREP

    ASET 7
    SPOP
    ASET 6
    SPOP
    ASET 5
    SPOP
    ASET 4
    SPOP
    ASET 3
    SPOP
    ASET 2
    SPOP
    ASET 1
    SPOP
    ASET 0
    SPOP

    JMP

;
; Pops registers $a8-$a15 from the stack
;
; Volatile registers:
; - Currently selected register
;
POPVOLATILEREGS:
    OS_SYSCALL_RET_PREP

    ASET 15
    SPOP
    ASET 14
    SPOP
    ASET 13
    SPOP
    ASET 12
    SPOP
    ASET 11
    SPOP
    ASET 10
    SPOP
    ASET 9
    SPOP
    ASET 8
    SPOP

    JMP

;
; Pops registers $a0-$a15 from the stack
;
; Volatile registers:
; - Currently selected register
;
POPALLREGS:
    OS_SYSCALL_RET_PREP

    ASET 15
    SPOP
    ASET 14
    SPOP
    ASET 13
    SPOP
    ASET 12
    SPOP
    ASET 11
    SPOP
    ASET 10
    SPOP
    ASET 9
    SPOP
    ASET 8
    SPOP
    ASET 7
    SPOP
    ASET 6
    SPOP
    ASET 5
    SPOP
    ASET 4
    SPOP
    ASET 3
    SPOP
    ASET 2
    SPOP
    ASET 1
    SPOP
    ASET 0
    SPOP

    JMP

;
; Effectively halt the CPU
;
; Notes:
; -This function will never return to the caller.
;
HALT:
    OR 15
    HALT_LOOP:
        PORTOUT_SLEEP
        JMP HALT_LOOP
