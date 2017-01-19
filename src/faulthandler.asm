; asmsyntax=apricos
; ===================================
; ==                               ==
; ==    ApricotOS Fault Handler    ==
; ==                               ==
; ==          Revision 1           ==
; ==                               ==
; ==  (C) 2014  Nick Stones-Havas  ==
; ==                               ==
; ==  Handles general OS faults    ==
; ==  and exceptions.              ==
; ==                               ==
; ===================================
;
#name "FAULT_HANDLER"
#segment 0x02

#include "potatosinc.asm"
#include "osutil.asm"
#include "disp.asm"

; Routine pointers
.nearptr PRINTERR

; Print an error to the display given its 
; unique error id, then halt the CPU.
; $a8 - The code of the error to print.
;
; Volatile registers:
; $a8
; $a9
;  
PRINTERR:
    ASET 8
    SPUSH

    ; Set up the TTY for printing
    libdisp_TTY_MODE 0x03 8 ; End any previous TTY command
    libdisp_TTY_MODE 0x10 8 ; Disable the cursor
    AND 0
    PRTout 7
    libdisp_TTY_MODE 0x7F 8 ; Enable command repeat mode
    AND 0                   ; ...on PUTCHAR
    PRTout 7

    ; BUG: Terminal doesn't blank out the cursor if it's disabled. Manually accounted for here by printing a space.
    ADD 2
    SHFl 4
    PRTout 7      ; Print a space (0x20) to the terminal
    AND 0
    ADD 13
    PRTout 7      ; Print a return carriage to reset the cursor

    LDI ERR_PTRS  ; Set up $a8 for the upcoming call by setting it to the current segment address
    LDah
    ASET 9
    LDal
    SPOP ADD
    STal
    LD            ; $a9 will now hold the address of the string to print
    ASET 10
    OS_SYSCALL libdisp_PUTSTR 

    OS_SYSJUMP OSUTIL_HALT
    
; List of pointers to the error strings
ERR_PTRS:
    .nearptr ERR_000
    .nearptr ERR_001
    .nearptr ERR_002
    .nearptr ERR_003

; Error strings
ERR_000: .stringz "FLAGRANT SYSTEM ERROR "
ERR_001: .stringz "GENERAL SYSTEM FAULT "
ERR_002: .stringz "INVALID DISK IO: BAD TRACK # "
ERR_003: .stringz "INVALID DISK IO: BAD SEGMENT # "

; Temporary messages
ERR_SHELL: .stringz "WORK IN PROGRESS. NOTHING TO SEE HERE. \n"
