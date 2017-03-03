; asmsyntax=apricos
; ===================================
; ==                               ==
; == ApricotOS Filesystem storage  ==
; ==                               ==
; ==          Revision 1           ==
; ==                               ==
; ==  (C) 2017  Nick Stones-Havas  ==
; ==                               ==
; == Reserves space for Filesystem ==
; == storage blocks.               ==
; ==                               ==
; ===================================
;

#name "fsmem"
#segment 18

; NOTE: This data spans two segments

VOL_INFO:
.padseg 0x00

VOL_BITMAP:
.padseg 0x00
