; asmsyntax=apricos
; ===================================
; ==                               ==
; ==  ApricotOS Stage 1 Bootloader ==
; ==                               ==
; ==          Revision 1           ==
; ==                               ==
; == (C) 2014-17 Nick Stones-Havas ==
; ==                               ==
; ==                               ==
; == Provides a stage 1 bootloader ==
; == which loads a stage 2         ==
; == bootloader from the first     ==
; == logical disk and executes it. ==
; ==                               ==
; ===================================
;
#name "bootloader"
#segment 0

;=========================================
;==                                     ==
;==               MACROS                ==
;==                                     ==
;=========================================

; Clear the Screen
;
; Arguments:
; treg - Temporary register
;
; Volatile:
; Alters $mar
#macro CLS {
    LARl 0x12
    PRTout 7
    PRTout 7
}

#macro TTY_MODE mode {
    LARl mode
    PRTout 7
}


;=========================================
;==                                     ==
;==             MAIN ROUTINE            ==
;==                                     ==
;=========================================
;TODO: TTY should not have the cursor invisible by default
TTY_MODE 0x03   ; End any previous TTY command
CLS             ; Clear screen

; Use $a14 to hold the sleep period (we will use 1000ms, so $a14 must hold 100)
ASET 14
LARl 100

; Select first disk and try to read.
; Give up on 3rd attempt and print error

ASET 1    ; $a1 will hold a negation of the counter we want (-3)
LARl 0xFD ; 0xFD is -3

ASET 0  ; Use $a0 to hold the ID of disk 0
AND 0
LOAD_DISK:
ASET 0
PRTout 0x03

; Get disk status
ASET 2
PRTin 0x03

; Check if it is equal to -1 (or -1 + 0 = 0)
ADD 1
BRnp CHECK_DISK

; Increment counter, pause, and jump if counter is negative or zero
ASET 14
PRTout 0x00
ASET 1
ADD 1
BRnz LOAD_DISK
; If counter is positive, print an error and halt.
ASET 8
LARl DISK_READ_ERROR
JMP PRINT_ERROR

; Check that the disk is bootable
CHECK_DISK:
; Select track 0
ASET 15
AND 0
PRTout 0x04

; NOTE: The disk paging sector is 0xFE
LAh 0xFE   ; Use $a15 to hold the base address of the disk paging region
LDah

ASET 0     ; Use $a0 to hold the disk segment number we want to read
LARl 0x3E

; Load sector 0x3E
PRTout 0x05

; Check that the first 4 bytes of this sector are 0xC0, 0x30, 0x0C, and 0x03 (xoring them together will produce 0xFF)
ASET 15
STah
AND 0
STal

ASET 10
LD        ; Load first char
SPUSH
LDal
ADD 1
STal
LD        ; Load second char
SPUSH
LDal
ADD 1
STal
LD        ; Load third char
SPUSH
LDal
ADD 1
STal
LD        ; Load fourth char
SPOP XOR  ; Pop the other three characters
SPOP XOR
SPOP XOR
ADD 1     ; Adding 1 should make it equal to zero

BRz BOOT_CODE_CHECK

; Disk is not valid
ASET 8
LARl DISK_FORMAT_ERROR
JMP PRINT_ERROR

BOOT_CODE_CHECK:

; Check that the last 2 bytes of this sector are 0xAA and 0x55 (xoring them together will produce 0xFF)
ASET 15
LDah
;STah
STal   ; Load the first byte
ASET 10
LD
SPUSH

; Load the second byte
LDal
ADD 1
STal
LD
SPOP XOR
ADD 1   ; Adding 1 should make it equal to zero
BRz COPY_LOADER

; Disk is not bootable
ASET 8
LARl DISK_NOT_BOOTABLE_ERROR
JMP PRINT_ERROR


; Disk is bootable. Copy the first 128 sectors into memory.
COPY_LOADER:

; Print a loading message
ASET 9   ; We need to print this value before every character
AND 0
ASET 8
LARl LOADING
LAh LOADING
PRINT_LOAD_MSG:
    STal
    SPUSH
    LD
    BRz PRINT_LOAD_MSG_END
    ASET 9
    PRTout 0x07
    ASET 8
    PRTout 0x07
    SPOP
    ADD 1
    JMP PRINT_LOAD_MSG
PRINT_LOAD_MSG_END:
SPOP




ASET 1     ; Use $a1 to store the value of -4 (negative number of sectors we want to load)
LARl 252    ; On a signed 8-bit machine, this is equivalent to -4.
ASET 0     ; Use $a0 to store the sector currently being read from disk (the block being written to is this + 1)
AND 0
LOADER_COPY_LOOP:
    ASET 0
    PRTout 0x05    ; Load the next sector from disk
    ADD 1          ; Increment sector (this now points to the sector we are writing to in memory)
    ASET 3         ; Use $a3 as a counter for the inner copy loop which must run exactly 256 times (increment until it overflows back to zero)
    AND 0
    COPY_SEGMENT_LOOP:
        STal                    ; Set sector local address
        ASET 15                 ; Set sector address to disk paging area
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

; Set the address of the first loaded segment, and prepare to jump to it
LAh 1
LAl 0

; Jump to first loaded segment
JMP




; Routine to print an error message and halt
; $a8 must hold the local address of the message to print
;
; It is expected that the mar already contains the message segment number
PRINT_ERROR:
    ; Write 0x7F to the TTY in order to enable line mode
    ASET 15
    LARl 0x7F
    PRTout 0x07
    AND 0
    STah   ; Make sure we have the right segment address
    PRTout 0x07

    ASET 8
    PRINT_LOOP:
        STal
        SPUSH
        LD
        BRz PRINT_END
        PRTout 0x07
        SPOP
        ADD 1
        JMP PRINT_LOOP
    PRINT_END:
    ; Disable TTY line mode
    ASET 15
    AND 0
    ADD 3
    PRTout 0x07

    ; Halt
    ASET 14
    HALT:
    PRTout 0x00
    JMP HALT



; Messages
DISK_READ_ERROR:   .stringz  "Disk read error!"
DISK_NOT_BOOTABLE_ERROR: .stringz  "Disk 0 is not bootable!"
DISK_FORMAT_ERROR: .stringz  "Disk 0 is not valid!"
LOADING: .stringz "Loading ApricotOS..."
