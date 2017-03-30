; asmsyntax=apricos
; ===================================
; ==                               ==
; ==     ApricotOS Disk Storage    ==
; ==           Allocator           ==
; ==                               ==
; ==          Revision 1           ==
; ==                               ==
; ==  (C) 2017 Nick Stones-Havas   ==
; ==                               ==
; ==                               ==
; ==  Provides a collection of     ==
; ==  storage allocation routines. ==
; ==                               ==
; ===================================
;

#name "diskalloc"
#segment 7

.nearptr CHECK_SECTOR
.nearptr AUTO_ALLOCATE_SECTOR

; Check if a disk sector is free or not.
; $a8 - The track number of the sector to check
; $a9 - The sctor number to check
;
; Returns:
; $a8 - Zero if the sector is free, non-zero otherwise
;
; Volatile registers:
; TODO
CHECK_SECTOR:
    ; TODO
    NOP

; Find and allocate the first available sector
;
; Returns:
; $a8  - Non-zero if the operation was successful, zero otherwise
; $a9  - The track number of the allocated sector
; $a10 - The sector number of the allocated sector
;
; Volatile registers:
; TODO
AUTO_ALLOCATE_SECTOR:
    ; TODO
    NOP

; Free a given sector
;
; $a8 - The track number of the sector to free
; $a9 - The sector number to free
;
; Volatile registers:
; TODO
FREE_SECTOR:
    ; TODO
    NOP
