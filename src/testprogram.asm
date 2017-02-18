; asmsyntax=apricos

; Sample program for ApricotOS
;
; To execute this program, assemble it along with 
; the rest of the OS, and execute it by entering
; 'memexec 1500' ino the shell.

#segment 0x15
#name "testprogram"

#include "apricotos.asm"
#include "disp.asm"

LDI MESSAGE
ASET 8
LDah
ASET 9
LDal
ASET 10
OS_CALLFUNC LIBDISP_PUTSTR

OS_PROG_EXIT

MESSAGE: .stringz "Hello! You have just executed ApricotOS' first program!\n"
