; asmsyntax=apricos
; ===================================
; ==                               ==
; ==  ApricotOS Filesystem state   ==
; ==         and buffers           ==
; ==                               ==
; ==  Reserves memory for the      ==
; ==  filesystem driver's state    ==
; ==  and its sector buffers.      ==
; ==                               ==
; ===================================
;

#name "fsbuf"
#segment 29

; NOTE: This data spans five segments (29-33)

;
; Segment 29: driver state
;
MOUNTED:    .fill 0          ; Non-zero if a valid filesystem is mounted
VOLSTATE:   .fill 1          ; Result of the last mount: 0 = OK, 1 = no signature, 2 = not formatted
PATH_DEPTH: .fill 1          ; Number of entries on the path stack (1 = root only)
NAMEBUF:    .blockw 6 0      ; Parsed name (6 bytes, NUL padded)
NAMEBUF2:   .blockw 6 0      ; Second parsed name (MV/CP destination)
VOLNAME:    .blockw 8 0      ; Parsed volume name (8 bytes, NUL padded)
VARS:       .blockw 16 0     ; Scratch variables for the driver routines

.blockw 89 0                 ; Pad so that PATH_STACK starts at offset 0x80

; Path stack: 16 entries of 8 bytes each. Every entry is a copy of the
; directory entry of a directory on the current path. Entry 0 is the root
; (track 1, sector 0) and is never overwritten.
PATH_STACK:
.fill 0x81
.fill 0x00
.blockw 126 0

;
; Segment 30: copy of the working directory's sector
;
DIRBUF:
.padseg 0x00

;
; Segment 31: file metadata sector
;
METABUF:
.padseg 0x00

;
; Segment 32: file data sector
;
DATABUF:
.padseg 0x00

;
; Segment 33: second file metadata sector (CP source)
;
METABUF2:
.padseg 0x00
