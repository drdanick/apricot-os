; asmsyntax=apricos
; ===================================
; ==                               ==
; ==    ApricotOS shell storage    ==
; ==            labels             ==
; ==                               ==
; ==          Revision 1           ==
; ==                               ==
; == (C) 2014-17 Nick Stones-Havas ==
; ==                               ==
; ==                               ==
; ==  Provides labels for shell    ==
; ==  variables and data storage.  ==
; ==                               ==
; ===================================
;
#name "shellmem"
#segment 11

; Directory stack entry structure:
; - Track Number:    1 byte
; - Sector Number:   1 byte
; - Name string ptr: 2 bytes
;
; Total entry size: 4 bytes
;
DIRSTACKPTR: .nearptr DIRSTACK  ; Directory stack pointer
DIRSTACK: .blockw 64 0          ; 16 entry directory stack
DIRSTACK_END:

CMDBUFF: .blockw 128 0          ; Command buffer
CMDBUFFEND: .fill 0             ; Guarantee a null terminator for the buffer


;====================
;  SEGMENT BOUNDARY
;====================
.padseg 0x00


;============================
;=                          =
;=       SHELL STRINGS      =
;=                          =
;============================

PROMPT:      .stringz "\n>"
GREET:       .stringz "ApricotOS PIE shell [Version 0.0.1]\n(C) Copyright 2014-2018 Nick Stones-Havas\n"
UNKNOWN_CMD: .stringz "BAD COMMAND OR FILENAME\n"
HELP_MSG:    .stringz "KNOWN COMMANDS:\n"
HI:          .stringz "Hello Sailor...\n"
