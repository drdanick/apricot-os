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

#include "shell.asm"
#include "potatosinc.asm"

; Execute the shell
OS_SYSCALL SHELL_MAIN
