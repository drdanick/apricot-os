; asmsyntax=apricos
; ===================================
; ==                               ==
; ==       ApricotOS shell         ==
; ==                               ==
; ==          Revision 1           ==
; ==                               ==
; == (C) 2014-17 Nick Stones-Havas ==
; ==                               ==
; ==                               ==
; ==  Provides the main user       ==
; ==  interface for ApricotOS.     ==
; ==                               ==
; ===================================
;
#name "shell"
#segment 15

#include "apricotosint.asm"
#include "shellutil.asm"
#include "shellmem.asm"
#include "shellcmds.asm"
#include "osutil.asm"
#include "memutil.asm"
#include "disp.asm"
#include "portout.asm"

.nearptr MAIN


; Init code
MAIN:
    ;OS_SYSCALL OSUTIL_PUSHREGS
    OS_SYSCALL LIBDISP_TTYRESET

    ; Put the TTY into character line mode
    LARl 0x7F
    PORTOUT_TTY_WRITE
    AND 0
    PORTOUT_TTY_WRITE



    ; Print the greeting
    ASET 8
    LARh SHELLMEM_GREET
    ASET 9
    LARl SHELLMEM_GREET
    ASET 10
    OS_SYSCALL LIBDISP_PUTSTR

    ;JMP SHELL_RUN


    ;OS_SYSJUMP OSUTIL_HALT
    ;NOP

; Main shell routine
SHELL_RUN:
    OS_SYSCALL SHELLUTIL_PRINTPROMPT

    ; Enable the cursor
    AND 0
    ADD 3
    PORTOUT_TTY_WRITE
    LARl 0x10
    PORTOUT_TTY_WRITE
    PORTOUT_TTY_WRITE
    OS_SYSCALL SHELLUTIL_READLINE

    ; Reset the TTY mode
    LARl 3
    PORTOUT_TTY_WRITE

    ; Disable the cursor
    LARl 0x10
    PORTOUT_TTY_WRITE
    AND 0
    PORTOUT_TTY_WRITE

    ; Reenable line mode
    LARl 0x7F
    PORTOUT_TTY_WRITE
    AND 0
    PORTOUT_TTY_WRITE

    ; Don't bother doing anything if the input was empty
    ASET 15
    BRz SHELL_RUN

    ASET 11   ; Hold the constant value of -32 (ASCII space)
    LARl 224

    ASET 13
    STah

    ; Backup the segment local address of the input string
    ASET 14
    STal
    SPUSH



    ; Find the first space character, and replace it with a null character (this marks the boundary between command and argument list).
    MARK_ARGS:
        ASET 12
        LD
        BRz MARK_ARGS_END

        ASET 11
        SPUSH
        ASET 12
        SPOP ADD
        BRnp NOMARK

        MARK:
            ASET 11
            AND 0
            ST
            ASET 14
            ADD 1
            JMP MARK_ARGS_END
        NOMARK:
        ASET 14
        ADD 1
        STal
        JMP MARK_ARGS
    MARK_ARGS_END:

    ASET 13
    SPUSH
    SPUSH
    ASET 8   ; The segment address of both the command and argument strings
    SPOP
    ASET 3
    SPOP     ; Same as $a8
    ASET 9   ; The segment local address of the command string
    SPOP
    ASET 14
    SPUSH
    ASET 4  ; The segment local address of the argument string
    SPOP

    LAh EXECUTE_COMMAND
    LAl EXECUTE_COMMAND
    JMP

EXECUTE_COMMAND:
    ; Prepare a return address for command functions to jump back to
    ASET 1
    LARh SHELL_RUN
    SPUSH
    LARl SHELL_RUN
    SPUSH

    ; Loop through the command header array and check if the inputted command is any of those
    LAh SHELLCMDS_CMD_ARRAY
    LAl SHELLCMDS_CMD_ARRAY
    aset 0
    LDah
    ASET 1
    LDal

    ASET 2
    EXECUTE_LOOP:
        LD
        BRz COMMAND_NOMATCH

        ; Push the command routine address to the stack
        STal
        LD
        SPUSH
        LDal
        ADD 1
        STal
        LD
        SPUSH

        ; Get the address of the command string
        ASET 10
        LDah
        ASET 11
        LDal
        ADD 1

        ASET 13
        OS_SYSCALL MEMUTIL_STRCMP

        ASET 13
        BRnp COMMAND_MATCH

        ASET 0
        STah
        ASET 1
        ADD 1
        STal

        ASET 2
        SPOP
        SPOP

        JMP EXECUTE_LOOP
    COMMAND_NOMATCH:

    ; Command is not a shell command
    ; In the future, the filesystem will be checked for a program
    ; with the given name. For now, just print an error.
    ASET 8
    LARh SHELLMEM_UNKNOWN_CMD
    ASET 9
    LARl SHELLMEM_UNKNOWN_CMD
    ASET 10
    OS_SYSCALL LIBDISP_PUTSTR

    SPOP ; Clear the return address from the stack
    STal
    SPOP
    STah
    JMP

    COMMAND_MATCH:
    ASET 0
    SPOP
    STal
    SPOP
    STah
    ASET 4
    SPUSH
    ASET 8
    SPOP

    JMP
