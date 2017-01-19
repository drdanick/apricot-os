; asmsyntax=apricos
; ===================================
; ==                               ==
; ==   ApricotOS DiskIO routines   ==
; ==                               ==
; ==          Revision 1           ==
; ==                               ==
; == (C) 2014-17 Nick Stones-Havas ==
; ==                               ==
; ==                               ==
; ==  Provides a collection of     ==
; ==  Disk IO utility routines.    ==
; ==                               ==
; ===================================
;
#name "diskio"
#segment 0x06

#include "potatosinc.asm"
#include "faulthandler.asm"
#include "osutil.asm"
#include "memutil.asm"

; Macro to select a disk track
;
; Arguments:
; track - The track number to select
; 
; Notes:
; The currently selected accumulator is used 
; as temporary storage.
#macro TRACKSEL track {
    AND 0
    ADD track
    PRTout 0x04
}

; Function pointers
.nearptr COPYFROMDSK
.nearptr COPYTODSK
.nearptr COPYBULKFROMDSK
.nearptr COPYBULKTODSK


;
; Copies a segment from the currently selected track 
; into memory.
; $a8 - The source disk segment number
; $a9 - The destination memory segment number
;
; Volatile registers:
; $a8
; $a9
; $a10
; $a11
;
COPYFROMDSK:
    ASET 8
    PRTout 0x05

    ; Check that the segment number is valid by masking out valid range bits
    SPUSH
    LAl 0x70   ; 0x70 masks away all but the invalid segment number bits. Valid values will mask to 0.
    LDal
    SPOP AND
    BRnp SEGNUM_ERROR
    
    LAh 0xFE   ; Use $a8 to hold the base address of the disk paging region
    LDah

    ASET 10
    OS_SYSCALL MEMUTIL_SEGCPY

    OS_SYSCALL_RET


;
; Copies a segment of memory into a given segment of 
; the currently selected disk track. 
; $a8 - The source memory segment number
; $a9 - The destination disk segment number
;
; Volatile registers:
; $a8
; $a9
; $a10
; $a11
;
COPYTODSK:
    ASET 9
    SPUSH      ; Save this for later

    ; Check that the segment number is valid by masking out valid range bits
    SPUSH      ; We need the segment number in the stack again for this operation
    LAl 0x70   ; 0x70 masks away all but the invalid segment number bits. Valid values will mask to 0.
    LDal
    SPOP AND
    BRnp SEGNUM_ERROR
    
    LAh 0xFE   ; Use $a9 to hold the base address of the disk paging region
    LDah

    ASET 10
    OS_SYSCALL MEMUTIL_SEGCPY
    
    ; Write the data back to disk at the given segment
    SPOP
    PRTout 0x06
    
    OS_SYSCALL_RET


;
; Copies a series of disk segments into memory 
; starting from a given track and segment number.
; $a8  - The source disk segment number
; $a9  - The destination memory segment number
; $a10 - The source disk track number
; $a11 - The number of segments to copy
;
; Volatile registers:
; $a8
; $a9
; $a10
; $a11
;
COPYBULKFROMDSK:
    ; Use $a0, $a1, $a2, $a3 in place of $a8, $a9, $a10, and $a11
    ; Store the current values onto the stack
    OS_SYSCALL OSUTIL_PUSHREGSANDCOPY

    ; Negate $a3
    ASET 3
    NOT
    ADD 1

    CBFD_COPYLP:
        ; Check validity of the track number by masking out valid range bits
        ASET 2
        SPUSH        ; Push twice as we need the original value after this operation
        SPUSH
        LAl 0x30     ; 0x30 masks out valid track bits
        SPOP AND
        BRnp TRACKNUM_ERROR
        SPOP         ; Restore the track number
        PRTout 0x04  ; Select the track

    CBFD_COPYLP_NOSETTRACK: ; Jump to this if we don't need to set the track
        ASET 3
        BRz CBFD_COPYLP_END
        ADD 1
        
        ; Set up $a8 and $a9
        ASET 0
        SPUSH
        ASET 8
        SPOP
        ASET 1
        SPUSH
        ASET 9
        SPOP

        ASET 10     ; Select temporary register for call
        OS_LOCALSYSCALL COPYFROMDSK

        ; Increment the source and destination segment
        ASET 1
        ADD 1
        ; TODO: System error if $a1 overflows
        ASET 0
        ADD 1
        ; Check that the disk segment number is valid by masking out valid range bits
        SPUSH      ; Push the segment number twice so we can restore it afterwards
        SPUSH
        ASET 10    ; Use $a10 as a temp register for this operation
        LAl 0x70   ; 0x70 masks away all but the invalid segment number bits. Valid values will mask to 0.
        LDal
        SPOP AND
        ASET 0
        SPOP       ; Restore the segment number
        ASET 10
        ; Continue without setting a new track if the segment number is in range
        BRz CBFD_COPYLP_NOSETTRACK

        ; ...otherwise, set the segment number to zero, and increment the track number
        ASET 0
        AND 0
        ASET 2
        ADD 1
        BRnzp CBFD_COPYLP
    CBFD_COPYLP_END:

    ; Restore the old values of $a0, $a1, $a2, and $a3
    OS_SYSCALL OSUTIL_POPREGS
    OS_SYSCALL_RET


;
; Copies a series of segments from memory to disk.
; $a8  - The source memory segment number
; $a9  - The destination disk segment number
; $a10 - The destination disk track number
; $a11 - The number of segments to copy
;
; Volatile registers:
; $a8
; $a9
; $a10
; $a11
;
COPYBULKTODSK:
    ; Use $a0, $a1, $a2, $a3 in place of $a8, $a9, $a10, and $a11
    ; Store the current values onto the stack
    OS_SYSCALL OSUTIL_PUSHREGSANDCOPY

    ; Negate $a3
    ASET 3
    NOT
    ADD 1

    CBTD_COPYLP:
        ; Check validity of the track number by masking out valid range bits
        ASET 2
        SPUSH        ; Push twice as we need the original value after this operation
        SPUSH
        LAl 0x30     ; 0x30 masks out valid track bits
        SPOP AND
        BRnp TRACKNUM_ERROR
        SPOP         ; Restore the track number
        PRTout 0x04  ; Select the track

    CBTD_COPYLP_NOSETTRACK: ; Jump to this if we don't need to set the track
        ASET 3
        BRz CBTD_COPYLP_END
        ADD 1
        
        ; Set up $a8 and $a9
        ASET 0
        SPUSH
        ASET 8
        SPOP
        ASET 1
        SPUSH
        ASET 9
        SPOP

        ASET 10     ; Select temporary register for call
        OS_LOCALSYSCALL COPYTODSK

        ; Increment the source and destination segment
        ASET 1
        ADD 1
        ; TODO: System error if $a1 overflows
        ASET 0
        ADD 1
        ; Check that the disk segment number is valid by masking out valid range bits
        SPUSH      ; Push the segment number twice so we can restore it afterwards
        SPUSH
        ASET 10    ; Use $a10 as a temp register for this operation
        LAl 0x70   ; 0x70 masks away all but the invalid segment number bits. Valid values will mask to 0.
        LDal
        SPOP AND
        ASET 0
        SPOP       ; Restore the segment number
        ASET 10
        ; Continue without setting a new track if the segment number is in range
        BRz CBTD_COPYLP_NOSETTRACK

        ; ...otherwise, set the segment number to zero, and increment the track number
        ASET 0
        AND 0
        ASET 2
        ADD 1
        BRnzp CBTD_COPYLP
    CBTD_COPYLP_END:

    ; Restore the old values of $a0, $a1, $a2, and $a3
    OS_SYSCALL OSUTIL_POPREGS
    OS_SYSCALL_RET







; Handle track number errors
TRACKNUM_ERROR:
    ASET 8
    LAl 0x02
    LDal
    OS_SYSJUMP FAULT_HANDLER_PRINTERR 

; Handle segment number errors
SEGNUM_ERROR:
    ASET 8
    LAl 0x03
    LDal
    OS_SYSJUMP FAULT_HANDLER_PRINTERR 
