; asmsyntax=apricos
; ===================================
; ==                               ==
; ==   ApricotOS Internal System   ==
; ==             Header            ==
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

; Macro for library function calls
;
; Arguments:
; Func - Label of function
;
; Notes:
; -The currently selected accumulator will 
; be used as temporary storage.
#macro SYSCALL Func {
    ; Push the return address segment to the stack
    LDI OS_SYSCALL_RETURN       ; LDI will load $mar with the full return address
    LDah
    SPUSH
    LDal
    SPUSH

    ; Load the address of the function to be called
    LAh Func
    LAl Func
    JMP
    SYSCALL_RETURN:
}

; Macro for library function jumps
;
; Arguments:
; Func - Label of the function being jumped to
;
; Notes:
; - This macro will not set up the stack 
; for a SYSCALL_RET. Only use with functions 
; that never return to the caller.
#macro SYSJUMP Func {
    LAh Func
    LAl Func
    JMP
}

; Macro for local function calls
;
; Arguments:
; Func - Label of function
;
; Notes:
; -The callee must be in the same segment as the caller
; -The currently selected accumulator will 
; be used as temporary storage.
#macro LOCALSYSCALL Func {
    LDI OS_LOCALCALL_RETURN     ; LDI will load $mar with the full return address
    LDah
    SPUSH
    LDal
    SPUSH

    ; Load the address of the function to be called
    LAl Func
    JMP
    LOCALCALL_RETURN:
}

; Macro for returning from a syscall
;
; Notes:
; -The currently selected accumulator will 
; be used as temporary storage.
#macro SYSCALL_RET {
    SPOP
    STal
    SPOP
    STah
    JMP
}

; Macro for setting up $mr in preparation for a syscall return
;
; Notes:
; -The currently selected accumulator will 
; be used as temporary storage.
#macro SYSCALL_RET_PREP {
    SPOP
    STal
    SPOP
    STah
}
