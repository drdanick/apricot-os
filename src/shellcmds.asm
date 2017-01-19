; asmsyntax=apricos
; ===================================
; ==                               ==
; ==    ApricotOS shell command    ==
; ==           routines            ==
; ==                               ==
; ==          Revision 1           ==
; ==                               ==
; == (C) 2014-17 Nick Stones-Havas ==
; ==                               ==
; ==                               ==
; ==  Routines to handle shell     ==
; ==  commands.                    ==
; ==                               ==
; ===================================
;
#name "shellcmds"
#segment 13

#include "potatosinc.asm"
#include "faulthandler.asm"
#include "disp.asm"
#include "shellmem.asm"

#macro SHELLCMD_RET {
    SPOP
    STal
    SPOP
    STah
    JMP
}


;=========================================
;==                                     ==
;==           COMMAND HEADERS           ==
;==                                     ==
;=========================================


; Pointers to the headers of the builtin shell commands
CMD_ARRAY:
.nearptr HI_H
.nearptr CD_H
.nearptr LS_H
.nearptr CP_H
.nearptr MV_H
.nearptr RM_H
.nearptr PWD_H
.nearptr CLS_H
.nearptr CAT_H
.nearptr ECHO_H
.nearptr TOUCH_H
.fill 0


; Command headers follow the following structure:
; 1 byte  - Segment number of command handler
; 1 byte  - Segment local address of command handler
; n bytes - Command string

HI_H:
.farptr HI
.stringz "HI"

CD_H:
.farptr CD
.stringz "CD"

LS_H:
.farptr LS
.stringz "LS"

CP_H:
.farptr CP
.stringz "CP"

MV_H:
.farptr MV
.stringz "MV"

RM_H:
.farptr RM
.stringz "RM"

PWD_H:
.farptr PWD
.stringz "PWD"

CLS_H:
.farptr CLS
.stringz "CLS"

CAT_H:
.farptr CAT
.stringz "CAT"

ECHO_H:
.farptr ECHO
.stringz "ECHO"

TOUCH_H:
.farptr TOUCH
.stringz "TOUCH"




;=========================================
;==                                     ==
;==       COMMAND HANDLER ROUTINES      ==
;==                                     ==
;=========================================
;
; Arguments:
; $a8 - Holds the address of the argument string
;


HI:
    LAh SHELLMEM_HI
    LAl SHELLMEM_HI
    ASET 8
    LDah
    ASET 9
    LDal
    ASET 10
    OS_SYSCALL LIBDISP_PUTSTR
    SHELLCMD_RET

CD:
    OS_SYSJUMP WIP

LS:
    OS_SYSJUMP WIP

CP:
    OS_SYSJUMP WIP

MV:
    OS_SYSJUMP WIP

RM:
    OS_SYSJUMP WIP

PWD:
    OS_SYSJUMP WIP

CLS:
    AND 0
    ADD 3
    PRTout 7
    LAl 0x12
    LDal
    PRTout 7
    PRTout 7
    LAl 0x7F
    LDal
    PRTout 7
    AND 0
    PRTout 7
    SHELLCMD_RET

CAT:
    OS_SYSJUMP WIP

ECHO:
    ASET 8
    SPUSH
    LAh SHELLMEM_CMDBUFF
    LDah
    ASET 9
    SPOP

    ASET 10
    OS_SYSCALL LIBDISP_PUTSTR

    SHELLCMD_RET

TOUCH:
    OS_SYSJUMP WIP


; Anything that jumps here is incomplete
WIP:
    LAh FAULT_HANDLER_ERR_SHELL
    LAl FAULT_HANDLER_ERR_SHELL
    ASET 8
    LDah
    ASET 9
    LDal

    ASET 10
    OS_SYSCALL LIBDISP_PUTSTR
    SHELLCMD_RET
