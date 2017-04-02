; asmsyntax=apricos
; ===================================
; ==                               ==
; ==  ApricotOS InPort IO Header   ==
; ==                               ==
; ==          Revision 1           ==
; ==                               ==
; ==  (C) 2017  Nick Stones-Havas  ==
; ==                               ==
; == Provides macros for reading   ==
; == from input ports.             ==
; ==                               ==
; ===================================
;
#name "portin"

#macro KBD_STATUS   { PRTin 1 }
#macro KBD_INPUT    { PRTin 2 }
#macro DISK_STATUS  { PRTin 3 }
#macro STATUS_REG   { PRTin 4 }
#macro STACK_PTR    { PRTin 5 }
