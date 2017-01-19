; asmsyntax=apricos
; ===================================
; ==                               ==
; ==  ApricotOS Stage 2 Bootloader ==
; ==                               ==
; ==          Revision 1           ==
; ==                               ==
; == (C) 2014-17 Nick Stones-Havas ==
; ==                               ==
; ==                               ==
; == Provides a stage 2 bootloader ==
; == which will load the remainder ==
; == of the OS after control is    ==
; == handed over from the stage 1  ==
; == bootloader.                   ==
; ==                               ==
; ===================================
;
#name "apricotosloader"
#segment 0x00

; This bootloader will copy itself into the first segment of memory, overwriting the primary 
; stage 1 bootloader. Afterwhich, the copied loader will be modified to load the rest of the OS 
; from disk into memory. The modified loader is then executed.



; The TTY should have been reset by the main bootloader, but to be certian,
; reset it anyway.
ASET 0
AND 0
ADD 0x03    ; End any previous TTY command
PRTout 7

LAl PHASE1_MARKER
PHASE2_MARKER:  ; Marks the branch that should be NOPd during the second phase of booting
BRnzp

;=========================================
;==                                     ==
;==               PHASE 2               ==
;==                                     ==
;=========================================

ASET 5   ; Use $a5 to hold the base address of the disk paging region
LAh 0xFE
LDah

ASET 1     ; Use $a1 to store the value of -61 (negative number of sectors we want to load)
LAl 195    ; On a signed 8-bit machine, this is equivalent to -61.
LDal
ASET 0     ; Use $a0 to store the sector currently being read from disk (the block being written to is this)
AND 0
LOADER_COPY_LOOP:
    ASET 0
    ADD 1
    PRTout 0x05    ; Load the next sector from disk
    ASET 3         ; Use $a3 as a counter for the inner copy loop which must run exactly 256 times (increment until it overflows back to zero)
    AND 0
    COPY_SEGMENT_LOOP:
        STal                    ; Set sector local address
        ASET 5                  ; Set sector address to disk paging area
        STah
        ASET 4                  ; Temporary register for loading values         
        LD                      ; Load from the disk paging area
        ASET 0                  ; Set the sector address to the sector we're writing to
        STah
        ASET 4
        ST                      ; Write to memory
        ASET 3                  ; Increment memory location being written to
        ADD 1
    BRnp COPY_SEGMENT_LOOP  ; Repeat if our counter hasn't overflown yet
    ASET 1
    ADD 1
BRnp LOADER_COPY_LOOP

LAl 0x7F    ; Enable repeat mode
LDal
PRTout 7
AND 0       ; Enable repeat mode on character output
PRTout 7

; Print a welcome message
LAh 0
LAl WELCOME
LDal
; Loop until the null character is read
WELCOME_LOOP:
    STal
    SPUSH
    LD
    BRz WELCOME_LOOP_END
    PRTout 7
    SPOP
    ADD 1
    BRnzp WELCOME_LOOP
WELCOME_LOOP_END:
SPOP

; Sleep for 3 seconds
LAl 100
LDal

; Port 0 sleeps for 10 * $a, so write to it 3 times for 3 seconds
PRTout 0
PRTout 0
PRTout 0

; Reset the TTY and clear the screen
ASET 0
AND 0
ADD 0x03    ; End any previous TTY command
PRTout 7
LAl 0x12    ; Clear the screen
LDal
PRTout 7
PRTout 7

; Prepare to branch to the first loaded segment
AND 0
STal
ADD 1
STah

; Zero the first 8 registers
AND 0
ASET 1
AND 0
ASET 2
AND 0
ASET 3
AND 0
ASET 4
AND 0
ASET 5
AND 0
ASET 6
AND 0
ASET 7
AND 0

; Select $a0 and branch to the first loaded segment
ASET 0
BRnzp



PHASE1_MARKER:  ; Marks code only executed during the first phase of booting

;=========================================
;==                                     ==
;==               PHASE 1               ==
;==                                     ==
;=========================================

; NOTE: $a0 is still selected at this point.

; Print the booting message
LAl 0x12    ; Clear the screen
LDal
PRTout 7
PRTout 7
LAl 0x7F    ; Enable repeat mode
LDal
PRTout 7
AND 0       ; Enable repeat mode on character output
PRTout 7

LAl MESSAGE
LDal
; Loop until the null character is read
MSG_LOOP:
    STal
    SPUSH
    LD
    BRz MSG_LOOP_END
    PRTout 7
    SPOP
    ADD 1
    BRnzp MSG_LOOP
MSG_LOOP_END:
SPOP


ASET 1    ; Use $a1 to hold the source segment number
AND 0
ADD 1
ASET 2    ; Use $a2 to hold the destination segment number
AND 0

; Loop until $a0 overflows
ASET 0
AND 0
BL_COPY_LP:
    STal
    ASET 1
    STah
    ASET 3    ; Use $a3 to hold the byte being copied
    LD 
    ASET 2
    STah
    ASET 3
    ST
    ASET 0
    ADD 1
BRnp BL_COPY_LP

; Overwrite the branch marker with a NOP instruction
LAl PHASE2_MARKER
AND 0
ST

; Execute the copied loader
STah
STal
BRnzp


MESSAGE: .stringz "Booting ApricotOS..."
WELCOME: .stringz "\nWelcome to ApricotOS!"
