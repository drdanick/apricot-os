; asmsyntax=apricos
; ===================================
; ==                               ==
; ==     ApricotOS init code       ==
; ==                               ==
; ==          Revision 1           ==
; ==                               ==
; == (C) 2014-17 Nick Stones-Havas ==
; ==                               ==
; ==                               ==
; ==  OS initialization code run   ==
; ==  directly after a successful  ==
; ==  boot.                        ==
; ==                               ==
; ===================================

#segment 1
#name "osinit"

#include "apricotosint.asm"
#include "shell.asm"
#include "memutil.asm"
#include "faulthandler.asm"

;
; We need to place a fault handler at the end of non-reserved memory.
; This handler will catch code that "runs away" from regular routines
; and into unnused space. Since 0x00 is effectively a NOP, the CPU will
; eventually trigger this handler.
; Since the bootloader can only copy about 61 segments, this needs to be
; done post-boot.
;

; Get the length of the fault handler to be placed at the end of memory
LDI RUNAWAY_HANDLER
ASET 8
LDah
SPUSH
ASET 9
LDal
SPUSH

; Get the length of the code block to copy.
; Since 0x00 is a NOP, it's most likely not
; going to appear in the code, so we can use
; strlen to get its length.
ASET 10
OS_SYSCALL MEMUTIL_STRLEN

; Copy the fault handler into memory
ASET 13
SPUSH
ASET 12
SPOP

ASET 9
SPOP
ASET 8
SPOP

ASET 10
LARl 253 ; Segment #253 is the last non reserved segment
ASET 11
AND 0

ASET 13
OS_SYSCALL MEMUTIL_MEMCPY


; Execute the shell
OS_SYSCALL SHELL_MAIN


; Code to be copied to the end of main memory space
RUNAWAY_HANDLER:
ASET 8
AND 0
ASET 9
OS_SYSJUMP FAULTHANDLER_PRINTERR
.fill 0
