; asmsyntax=apricos
; ===================================
; ==                               ==
; ==   ApricotOS Standard Header   ==
; ==                               ==
; ==          Revision 1           ==
; ==                               ==
; == (C) 2014-17 Nick Stones-Havas ==
; ==                               ==
; ==                               ==
; == Provides standard labels and  ==
; == macros for programs running   ==
; == under ApricotOS.              ==
; ==                               ==
; ===================================
;
#name "OS"

; Macro for function calls
;
; Arguments:
; Func - Label of function
;
; Notes:
; -$a15 will be used as temporary storage.
#macro CALLFUNC Func {
    ASET 15
    ; Push the return address segment to the stack
    LDI OS_CALLFUNC_RET       ; LDI will load $mar with the full return address
    LDah
    SPUSH
    LDal
    SPUSH

    ; Load the address of the function to be called
    LAh Func
    LAl Func
    JMP
    CALLFUNC_RET:
}

; Macro for returning from a function call
;
; Notes:
; -$a15 will be used as temporary storage
#macro FUNC_RETURN {
    ASET 15
    SPOP
    STal
    SPOP
    STah
    JMP
}

; Macro for exiting a program
;
; Notes:
; -$a15 will be used as temporary storage.
#macro PROG_EXIT {
    ASET 15
    SPOP
    STal
    SPOP
    STah
    JMP
}
