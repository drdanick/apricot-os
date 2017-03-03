; asmsyntax=apricos
; ===================================
; ==                               ==
; ==  ApricotOS OutPort IO Header  ==
; ==                               ==
; ==          Revision 1           ==
; ==                               ==
; ==  (C) 2017  Nick Stones-Havas  ==
; ==                               ==
; == Provides macros for writing   ==
; == to output ports.              ==
; ==                               ==
; ===================================
;
#name "portout"

#macro SLEEP            { PRTout 0 }
#macro DISK_TRACKSEL    { PRTout 4 }
#macro DISK_READSECTOR  { PRTout 5 }
#macro DISK_WRITESECTOR { PRTout 6 }
#macro TTY_WRITE        { PRTout 7 }
