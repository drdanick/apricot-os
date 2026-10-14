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
; The simulator loads this file at 0x0000 and starts it there. It must fit in
; one segment (256 bytes), because stage 2 copies itself over segment 0.
;
; What it does:
;   1. Sets up the TTY for printing.
;   2. Selects disk 0, trying three times, one second apart.
;   3. Reads track 0, sector 62 (volume information) and checks it:
;      bytes 0-3 must be the signature C0 30 0C 03, and bytes 254-255 the boot
;      flag AA 55.
;   4. Copies disk sectors 0-3 into memory segments 1-4, then jumps to 0x0100
;      (stage 2, s2boot.asm).
; If a step fails, it prints an error message and halts.
;
; Registers:
;   $a0  disk ID (0), then the sector to read / segment to write
;   $a1  negative counter: retries left, then sectors left to copy
;   $a8  always 0: the segment of the strings and return addresses
;   $a9  address of the string to print
;   $a14 100, the sleep time for retries and HALT (100 x 10 ms)
;   $a15 0xFE, the segment of the disk buffer (0xFE00-0xFEFF)
;
#name "bootloader"
#segment 0

;=========================================
;==                                     ==
;==               MACROS                ==
;==                                     ==
;=========================================

; Clear the Screen
#macro CLS {
    LARl 0x12
    PRTout 7
    PRTout 7
}

; Set the current TTY mode
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
; TTY setup: 03 (end any command), 12 12 (clear screen), 0C 02 (green text),
; 7F 00 (repeat mode: every byte from now on is a character to print).
TTY_MODE 0x03   ; End any previous TTY command
CLS             ; Clear screen

LARl 0x0C
PRTout 7
LARl 2
PRTout 7

ASET 8 ; Enable line mode, zero $a8, and enable line character output on TTY.
LARl 0x7F
PRTout 7
AND 0
PRTout 7

; Use $a14 to hold the sleep period (we will use 1000ms, so $a14 must hold 100)
ASET 14
LARl 100

; Select disk 0. The disk status port reads 0xFF while no disk is open.
; Try three times, one second apart, then give up with "Disk read error!".

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
ASET 9
LARl DISK_READ_ERROR

; Print the error message at $a9, then halt.
; It pushes HALT as the return address, so PRINT_STRING "returns" into HALT.
INVALID_DISK:
ASET 10
LARl HALT
SPUSH
JMP PRINT_STRING

; Read track 0, sector 62 (volume information) into the disk buffer at 0xFE00.
CHECK_DISK:
; Select track 0
ASET 15
AND 0
PRTout 0x04

; NOTE: The disk paging sector is 0xFE
LARl 0xFE  ; Use $a15 to hold the base address of the disk paging region

ASET 0     ; Use $a0 to hold the disk segment number we want to read
LARl 0x3E

; Load sector 0x3E
PRTout 0x05

; Check that the first 4 bytes of this sector are exactly 0xC0, 0x30, 0x0C, and 0x03.
; Each byte is the previous one shifted right by 2, and one more shift gives 0, so
; $a11 holds both the expected byte and the loop counter.
ASET 15
STah       ; $mr = 0xFE00 (this also leaves $a15 = 0 until the next check)
AND 0
STal

ASET 9     ; The message if a check fails
LARl DISK_FORMAT_ERROR

ASET 11
LARl 0xC0     ; Expected first byte
SIG_LOOP:
    SPUSH     ; $a11 is selected here on every pass
    ASET 10
    LD        ; Load the next signature byte
    SPOP XOR  ; Zero only if it matches
    BRnp INVALID_DISK
    LDal      ; $mr += 1
    ADD 1
    STal
    ASET 11
    SHFr 2    ; 0xC0 -> 0x30 -> 0x0C -> 0x03 -> 0
    BRnp SIG_LOOP

; Check that the last 2 bytes of this sector are 0xAA and 0x55.
; The second byte must be the complement of the first (a ^ b = 0xFF),
; and b ^ (b << 1) is 0xFF only for b = 0x55.
ASET 9
LARl DISK_NOT_BOOTABLE_ERROR

ASET 15
LDah      ; $a15 = 0xFE again
STal      ; $mr = 0xFEFE
ASET 10
LD        ; Load the first byte (a)
SPUSH
LDal
ADD 1
STal
LD        ; Load the second byte (b)
SPOP XOR  ; a ^ b
SPUSH
LD        ; b again
SPUSH
SHFl 1
SPOP XOR  ; b ^ (b << 1)
SPOP AND  ; 0xFF only if both are 0xFF
ADD 1     ; Adding 1 should make it equal to zero
BRnp INVALID_DISK

; Disk is bootable. Copy disk sectors 0-3 (still track 0) into memory segments 1-4.
COPY_LOADER:

; Print a loading message (PRINT_STRING returns to END_LOAD_MESSAGE)
ASET 9
LARl END_LOAD_MESSAGE
SPUSH
LARl LOADING
JMP PRINT_STRING
END_LOAD_MESSAGE:

ASET 1     ; Use $a1 to store the value of -4 (negative number of sectors we want to load)
LARl 252    ; On a signed 8-bit machine, this is equivalent to -4.
ASET 0     ; $a0 = the sector to read; after ADD 1 below, the segment to write it to
AND 0
LOADER_COPY_LOOP:
    ASET 0
    PRTout 0x05    ; Load the next sector from disk
    ADD 1          ; Increment sector (this now points to the sector we are writing to in memory)
    ASET 3         ; Use $a3 as a counter for the inner copy loop which must run exactly 256 times (increment until it overflows back to zero)
    AND 0
    ; Copy 0xFE00 + $a3 to ($a0 * 256) + $a3, through $a4
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


; Shared print routine.
; TTY must already be in line mode.
; Segment local return address must be on the stack.
; It returns with SPOP / STal / JMP: $mr's high byte is still $a8 (0), so the
; return lands in segment 0, and $mr is left pointing at the return address.
;
; $a8 - Segment number of string to print
; $a9 - Segment local address of string to print
;
; Volatile registers:
; $a9
;
PRINT_STRING:
    ASET 8
    STah
    ASET 9
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
    SPOP ; Pop residual address

    SPOP
    STal
    JMP

; Halt the CPU: sleep, then jump back here forever.
; It is only reached as PRINT_STRING's return address, which leaves $mr = HALT,
; so the bare JMP loops.
;
; $a14 - The sleep delay to use in the busy loop
;
HALT:
    ASET 14
    PRTout 0x00
    JMP


; Messages
DISK_READ_ERROR:   .stringz  "Disk read error!"
DISK_NOT_BOOTABLE_ERROR: .stringz  "Disk 0 not bootable!"
DISK_FORMAT_ERROR: .stringz  "Disk 0 not valid!"
LOADING: .stringz "Loading Operating System..."
