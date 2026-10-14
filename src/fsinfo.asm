; asmsyntax=apricos
; ===================================
; ==                               ==
; ==  ApricotOS Filesystem         ==
; ==  entry information (STAT)     ==
; ==                               ==
; ===================================
;
; Registers used by STAT and its helpers (saved with OSUTIL_PUSHREGS):
; $a0 - Entry offset in FSBUF_DIRBUF
; $a1 - Entry flags byte
; $a2 - Track of the entry's sector (directory or file metadata)
; $a3 - Sector of the entry's sector
; $a4-$a7 - Helper state (see STAT_DIR and WALK)
;
; Strings live in two tables, each within one page: labels (printed
; with PS) and other text (printed with PT).
;

#name "fsinfo"
#segment 52

#include "apricotosint.asm"
#include "osutil.asm"
#include "fsbuf.asm"
#include "fsdriver.asm"
#include "fsdir.asm"
#include "fspath.asm"
#include "disp.asm"
#include "portout.asm"


;
; STAT: print everything stored about an entry of the working directory.
; $a8 - The segment of the argument string (the name)
; $a9 - The segment local address of the argument string
;
; Returns:
; $a8 - Status: 0, 2 (not found), 4 (bad name) or 12 (missing argument)
;
; Volatile registers:
; $a8-$a15
;
STAT:
    ASET 10
    LARh FSBUF_NAMEBUF
    ASET 11
    LARl FSBUF_NAMEBUF
    ASET 12
    OS_SYSCALL FSDIR_PARSE_NAME
    ASET 8
    BRnp ST_RET

    OS_SYSCALL FSDIR_LOAD_CWD
    ASET 8
    LARh FSBUF_NAMEBUF
    ASET 9
    LARl FSBUF_NAMEBUF
    ASET 10
    OS_SYSCALL FSDIR_FIND_ENTRY
    ASET 8
    BRnp ST_RET

    OS_SYSCALL OSUTIL_PUSHREGS
    ASET 9
    SPUSH
    ASET 0
    SPOP               ; $a0 = entry offset
    LAh FSBUF_DIRBUF
    STal
    ASET 1
    LD                 ; $a1 = flags byte
    ASET 8
    LARh FSBUF_DIRBUF
    ASET 0
    SPUSH
    ASET 9
    SPOP
    ASET 10
    OS_SYSCALL FSDIR_ENTRY_TS
    ASET 8
    SPUSH
    ASET 2
    SPOP               ; $a2 = track
    ASET 9
    SPUSH
    ASET 3
    SPOP               ; $a3 = sector
    ASET 10
    LARh FSBUF_METABUF
    ASET 11
    OS_SYSCALL FS_READ_SECTOR

    ; NAME
    ASET 9
    LARl S_NAME
    ASET 10
    OS_SYSCALL PS
    ASET 8
    OS_SYSCALL PRINT_NAME
    ASET 8
    OS_SYSCALL NEWLINE

    ASET 8
    OS_SYSCALL STAT_TAIL

    ASET 9
    OS_SYSCALL OSUTIL_POPREGS
    ASET 8
    AND 0

    ST_RET:
    ASET 9
    OS_SYSCALL_RET

;
; Print the name of the entry at offset $a0 of FSBUF_DIRBUF (up to 6
; characters).
;
; Volatile registers:
; $a8-$a10
;
PRINT_NAME:
    ASET 0
    SPUSH
    ASET 9
    SPOP
    ADD 2
    ASET 10
    LARl 0xFA
    LAh FSBUF_DIRBUF
    PN_LP:
        ASET 9
        STal
        ASET 8
        LD
        BRz PN_END
        PORTOUT_TTY_WRITE
        ASET 9
        ADD 1
        ASET 10
        ADD 1
        BRnp PN_LP
    PN_END:
    ASET 8
    OS_SYSCALL_RET

;
; Print "S" unless the 16 bit count $a8:$a9 is exactly 1.
;
PRINT_S:
    ASET 8
    BRnp PRS_PRINT
    ASET 9
    NOT
    ADD 1
    NOT
    BRz PRS_RET
    PRS_PRINT:
    ASET 8
    LARl 0x53
    PORTOUT_TTY_WRITE
    PRS_RET:
    ASET 8
    OS_SYSCALL_RET

;
; Print a newline.
;
NEWLINE:
    ASET 8
    LARl 0x0A
    PORTOUT_TTY_WRITE
    OS_SYSCALL_RET

; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

;
; STAT helper: the PATH, TYPE and EXEC lines, the file or directory
; details, then the ENTRY line.
;
STAT_TAIL:
    ; PATH: the working directory's path (unless it is the root), '/', the name
    ASET 9
    LARl S_PATH
    ASET 10
    OS_SYSCALL PS
    LAh FSBUF_PATH_DEPTH
    LAl FSBUF_PATH_DEPTH
    ASET 8
    LD
    NOT
    ADD 1
    NOT
    BRz ST_PATH_ROOT
    OS_SYSCALL FSPATH_PRINT_PATH_NONL
    ST_PATH_ROOT:
    ASET 8
    LARl 0x2F
    PORTOUT_TTY_WRITE
    OS_SYSCALL PRINT_NAME
    ASET 8
    OS_SYSCALL NEWLINE

    ; TYPE
    ASET 9
    LARl S_TYPE
    ASET 10
    OS_SYSCALL PS
    ASET 9
    LARl S_FILE_NL
    ASET 1
    SPUSH
    ASET 8
    SPOP
    SHFl 2             ; Bit 5 (file) -> bit 7
    BRn ST_TYPE_PRINT
    ASET 9
    LARl S_DIR_NL
    ST_TYPE_PRINT:
    ASET 10
    OS_SYSCALL PT

    ; EXEC
    ASET 9
    LARl S_EXEC
    ASET 10
    OS_SYSCALL PS
    ASET 9
    LARl S_YES_NL
    ASET 1
    SPUSH
    ASET 8
    SPOP
    SHFl 1             ; Bit 6 (executable) -> bit 7
    BRn ST_EXEC_PRINT
    ASET 9
    LARl S_NO_NL
    ST_EXEC_PRINT:
    ASET 10
    OS_SYSCALL PT

    ; File or directory details
    ASET 1
    SPUSH
    ASET 8
    SPOP
    SHFl 2
    BRzp ST_IS_DIR
    OS_SYSCALL STAT_FILE
    JMP ST_ENTRY
    ST_IS_DIR:
    OS_SYSCALL STAT_DIR

    ST_ENTRY:
    ASET 8
    OS_SYSCALL STAT_ENTRY
    ASET 8
    OS_SYSCALL_RET

;
; Print "track/sector".
; $a8 - The track
; $a9 - The sector
;
; Volatile registers:
; $a8-$a11
;
PRINT_TS:
    ASET 9
    SPUSH
    ASET 10
    OS_SYSCALL LIBDISP_PUTNUM
    ASET 8
    LARl 0x2F
    PORTOUT_TTY_WRITE
    SPOP
    ASET 10
    OS_SYSCALL LIBDISP_PUTNUM
    ASET 8
    OS_SYSCALL_RET

; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

;
; STAT helper: the ENTRY line: slot OF 32 IN parent (parent's track/sector).
;
STAT_ENTRY:
    ASET 9
    LARl S_ENTRY
    ASET 10
    OS_SYSCALL PS
    ASET 0
    SPUSH
    ASET 8
    SPOP
    SHFr 3
    ADD 1              ; 1-based slot number
    ASET 9
    OS_SYSCALL LIBDISP_PUTNUM
    ASET 9
    LARl S_OF32IN
    ASET 10
    OS_SYSCALL PT
    ASET 8
    OS_SYSCALL FSPATH_PRINT_PATH_NONL
    ASET 9
    LARl S_LPAREN
    ASET 10
    OS_SYSCALL PT
    ASET 10
    OS_SYSCALL FSDIR_PATH_TOP
    ASET 10
    OS_SYSCALL PRINT_TS
    ASET 9
    LARl S_RPAREN_NL
    ASET 10
    OS_SYSCALL PT

    ASET 8
    OS_SYSCALL_RET

;
; WALK helper: if the current range has more than one block ($a7 bit 1),
; print "-" and its last block ($a5/$a6).
;
CLOSE_RANGE:
    ASET 7
    SPUSH
    ASET 8
    SPOP
    AND 2
    BRz CR_RET
    LARl 0x2D
    PORTOUT_TTY_WRITE
    ASET 5
    SPUSH
    ASET 8
    SPOP
    ASET 6
    SPUSH
    ASET 9
    SPOP
    ASET 10
    OS_SYSCALL PRINT_TS
    CR_RET:
    ASET 8
    OS_SYSCALL_RET

; WALK state
V_MODE:   .fill 0
V_BLOCKS: .fill 0
V_FRAGS:  .fill 0

;
; Print a label string.
; $a9 - The segment local address of the string
;
; Volatile registers:
; $a8-$a10
;
PS:
    ASET 8
    LARh S_NAME
    ASET 10
    OS_SYSCALL LIBDISP_PUTSTR
    ASET 8
    OS_SYSCALL_RET

;
; Print a text string.
; $a9 - The segment local address of the string
;
; Volatile registers:
; $a8-$a10
;
PT:
    ASET 8
    LARh S_FILE_NL
    ASET 10
    OS_SYSCALL LIBDISP_PUTSTR
    ASET 8
    OS_SYSCALL_RET

; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

;
; STAT helper: the lines for a directory (its sector is in FSBUF_METABUF).
; Uses $a4 = files, $a5 = directories.
;
STAT_DIR:
    ASET 4
    AND 0
    ASET 5
    AND 0
    LAh FSBUF_METABUF
    ASET 8             ; $a8 = entry offset
    AND 0
    SD_LP:
        STal
        ASET 9
        LD
        BRzp SD_NEXT   ; Free slot
        SHFl 2
        BRn SD_FILE
        ASET 5
        ADD 1
        JMP SD_NEXT
        SD_FILE:
        ASET 4
        ADD 1
        SD_NEXT:
        ASET 8
        ADD 8
        BRnp SD_LP

    ; ENTRIES: used OF 32 (files FILE(S), dirs DIRECTORY/DIRECTORIES)
    ASET 9
    LARl S_ENTRIES
    ASET 10
    OS_SYSCALL PS
    ASET 4
    SPUSH
    ASET 5
    SPUSH
    ASET 8
    SPOP
    SPOP ADD
    ASET 9
    OS_SYSCALL LIBDISP_PUTNUM
    ASET 9
    LARl S_OF32LP
    ASET 10
    OS_SYSCALL PT
    ASET 4
    SPUSH
    ASET 8
    SPOP
    ASET 9
    OS_SYSCALL LIBDISP_PUTNUM
    ASET 9
    LARl S_FILE
    ASET 10
    OS_SYSCALL PT
    ASET 8
    AND 0
    ASET 4
    SPUSH
    ASET 9
    SPOP
    ASET 10
    OS_SYSCALL PRINT_S
    ASET 9
    LARl S_COMMA
    ASET 10
    OS_SYSCALL PT
    ASET 5
    SPUSH
    ASET 8
    SPOP
    ASET 9
    OS_SYSCALL LIBDISP_PUTNUM
    ASET 9
    LARl S_DIRECTOR
    ASET 10
    OS_SYSCALL PT
    ASET 9
    LARl S_IES
    ASET 5
    SPUSH
    ASET 8
    SPOP
    NOT
    ADD 1
    NOT                ; Zero if there is exactly one directory
    BRnp SD_PLURAL
    ASET 9
    LARl S_Y
    SD_PLURAL:
    ASET 10
    OS_SYSCALL PT
    ASET 9
    LARl S_RPAREN_NL
    ASET 10
    OS_SYSCALL PT

    ; SECTOR
    ASET 2
    SPUSH
    ASET 8
    SPOP
    ASET 3
    SPUSH
    ASET 9
    SPOP
    ASET 10
    LARl S_SECTOR_L
    ASET 11
    OS_SYSCALL FIELD_TS

    ASET 8
    OS_SYSCALL_RET

; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

;
; STAT helper: the lines for a file (its metadata is in FSBUF_METABUF).
;
STAT_FILE:
    ; SIZE
    LAh FSBUF_METABUF
    LAl 1
    ASET 8
    LD
    LAl 0
    ASET 9
    LD
    ASET 10
    LARl S_SIZE
    ASET 11
    LARl S_BYTE
    ASET 12
    OR 1
    ASET 13
    OS_SYSCALL FIELD16

    ; Count the blocks and fragments
    LAh V_MODE
    LAl V_MODE
    ASET 8
    AND 0
    ST
    OS_SYSCALL WALK

    ; BLOCKS: n (n*256 BYTES, unused UNUSED)
    ASET 9
    LARl S_BLOCKS
    ASET 10
    OS_SYSCALL PS
    ASET 8
    AND 0
    LAh V_BLOCKS
    LAl V_BLOCKS
    ASET 9
    LD
    ASET 10
    OS_SYSCALL LIBDISP_PUTNUM16
    ASET 9
    LARl S_LPAREN
    ASET 10
    OS_SYSCALL PT
    LAh V_BLOCKS
    LAl V_BLOCKS
    ASET 8
    LD
    ASET 9
    AND 0
    ASET 10
    OS_SYSCALL LIBDISP_PUTNUM16
    ASET 9
    LARl S_BYTES_C
    ASET 10
    OS_SYSCALL PT

    ; unused = blocks*256 - size = (blocks + ~high + (low == 0)) : -low
    LAh FSBUF_METABUF
    LAl 0
    ASET 9
    LD
    NOT
    ADD 1              ; $a9 = -low (zero exactly when low is zero)
    LAl 1
    ASET 8
    LD
    NOT
    ASET 9
    BRnp SF_NO_CARRY
    ASET 8
    ADD 1
    SF_NO_CARRY:
    LAh V_BLOCKS
    LAl V_BLOCKS
    ASET 10
    LD
    SPUSH
    ASET 8
    SPOP ADD
    ASET 10
    OS_SYSCALL LIBDISP_PUTNUM16
    ASET 9
    LARl S_UNUSED
    ASET 10
    OS_SYSCALL PT

    ASET 8
    OS_SYSCALL STAT_FILE2
    ASET 8
    OS_SYSCALL_RET

; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

;
; STAT helper: the FRAGMENTS, ON DISK, METADATA and DATA lines for a file.
;
STAT_FILE2:
    ; FRAGMENTS
    ASET 8
    AND 0
    LAh V_FRAGS
    LAl V_FRAGS
    ASET 9
    LD
    ASET 10
    LARl S_FRAGS
    ASET 11
    AND 0
    ASET 12
    AND 0
    ASET 13
    OS_SYSCALL FIELD16

    ; ON DISK: blocks + 1 SECTOR(S)
    ASET 8
    AND 0
    LAh V_BLOCKS
    LAl V_BLOCKS
    ASET 9
    LD
    ADD 1
    ASET 10
    LARl S_ONDISK
    ASET 11
    LARl S_SECTOR
    ASET 12
    OR 1
    ASET 13
    OS_SYSCALL FIELD16

    ; METADATA
    ASET 2
    SPUSH
    ASET 8
    SPOP
    ASET 3
    SPUSH
    ASET 9
    SPOP
    ASET 10
    LARl S_META
    ASET 11
    OS_SYSCALL FIELD_TS

    ; DATA: the block ranges
    ASET 9
    LARl S_DATA
    ASET 10
    OS_SYSCALL PS
    LAh V_BLOCKS
    LAl V_BLOCKS
    ASET 8
    LD
    BRnp SF_RANGES
    ASET 9
    LARl S_NONE
    ASET 10
    OS_SYSCALL PT
    JMP SF_DATA_END
    SF_RANGES:
    LAh V_MODE
    LAl V_MODE
    ASET 8
    AND 0
    ADD 1
    ST
    OS_SYSCALL WALK
    SF_DATA_END:
    ASET 8
    OS_SYSCALL NEWLINE

    ASET 8
    OS_SYSCALL_RET

;
; Print a label, "track/sector", then a newline.
; $a8  - The track
; $a9  - The sector
; $a10 - The label (PS string)
;
; Volatile registers:
; $a8-$a11
;
FIELD_TS:
    ASET 8
    SPUSH
    ASET 9
    SPUSH
    ASET 10
    SPUSH
    ASET 9
    SPOP
    ASET 10
    OS_SYSCALL PS
    ASET 9
    SPOP
    ASET 8
    SPOP
    ASET 10
    OS_SYSCALL PRINT_TS
    ASET 8
    OS_SYSCALL NEWLINE
    ASET 8
    OS_SYSCALL_RET


; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

;
; STAT helper: walk the data block slots of FSBUF_METABUF.
; V_MODE = 0: count the blocks (V_BLOCKS) and fragments (V_FRAGS).
; V_MODE = 1: also print the blocks as ranges of consecutive sectors.
; Uses $a4 = slot offset, $a5/$a6 = previous track/sector,
; $a7 = bit 0: a block has been seen, bit 1: the current range has
; more than one block.
;
WALK:
    LAh V_BLOCKS
    LAl V_BLOCKS
    ASET 8
    AND 0
    ST
    LAl V_FRAGS
    ST
    ASET 7
    AND 0
    ASET 4
    LARl 2

    W_LP:
        ASET 8
        LARh FSBUF_METABUF
        ASET 4
        SPUSH
        ASET 9
        SPOP
        ASET 10
        OS_SYSCALL FSDIR_ENTRY_TS
        ASET 8
        BRz W_NEXT     ; Unused slot
        SPUSH          ; Keep this block's track and sector
        ASET 9
        SPUSH

        LAh V_BLOCKS
        LAl V_BLOCKS
        ASET 10
        LD
        ADD 1
        ST

        ; Is it the sector after the previous block?
        ASET 7
        SPUSH
        ASET 12
        SPOP
        AND 1
        BRz W_NEWFRAG
        ASET 5
        SPUSH
        ASET 11
        SPOP           ; $a11 = expected track
        ASET 6
        SPUSH
        ASET 10
        SPOP
        ADD 1          ; $a10 = expected sector
        SPUSH
        ASET 12
        LARl 0xC0      ; -64
        SPOP ADD
        BRnp W_NOWRAP
        ASET 10
        AND 0
        ASET 11
        ADD 1
        W_NOWRAP:
        ASET 8
        SPUSH
        ASET 11
        SPOP XOR
        BRnp W_NEWFRAG
        ASET 9
        SPUSH
        ASET 10
        SPOP XOR
        BRnp W_NEWFRAG
        ASET 7
        OR 2
        JMP W_SAVE

        W_NEWFRAG:
        LAh V_FRAGS
        LAl V_FRAGS
        ASET 10
        LD
        ADD 1
        ST
        LAl V_MODE
        LD
        BRz W_NEWFRAG_DONE
        ASET 8
        OS_SYSCALL CLOSE_RANGE
        ASET 7
        SPUSH
        ASET 12
        SPOP
        AND 1
        BRz W_FIRST
        ASET 8
        LARl 0x20
        PORTOUT_TTY_WRITE
        W_FIRST:
        ASET 9
        SPOP
        ASET 8
        SPOP
        SPUSH
        ASET 9
        SPUSH
        ASET 10
        OS_SYSCALL PRINT_TS
        W_NEWFRAG_DONE:
        ASET 7
        AND 0
        ADD 1

        W_SAVE:
        ASET 6
        SPOP
        ASET 5
        SPOP

        W_NEXT:
        ASET 4
        ADD 2
        BRnp W_LP

    LAh V_MODE
    LAl V_MODE
    ASET 8
    LD
    BRz W_RET
    OS_SYSCALL CLOSE_RANGE
    W_RET:
    ASET 8
    OS_SYSCALL_RET

; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

;
; Print a field: a label, a 16 bit number, an optional suffix (with "S"
; added unless the number is 1, if asked), then a newline.
; $a8  - The number (high byte)
; $a9  - The number (low byte)
; $a10 - The label (PS string)
; $a11 - The suffix (PT string), or 0 for none
; $a12 - Non-zero to pluralise the suffix
;
; Volatile registers:
; $a8-$a15
;
FIELD16:
    ASET 12
    SPUSH
    ASET 11
    SPUSH
    ASET 8
    SPUSH
    ASET 9
    SPUSH              ; Stack: plural flag, suffix, high, low
    ASET 10
    SPUSH
    ASET 9
    SPOP               ; $a9 = label
    ASET 10
    OS_SYSCALL PS
    ASET 9
    SPOP
    ASET 8
    SPOP
    SPUSH
    ASET 9
    SPUSH
    ASET 10
    OS_SYSCALL LIBDISP_PUTNUM16
    ASET 13
    SPOP               ; $a13 = low
    ASET 14
    SPOP               ; $a14 = high
    ASET 9
    SPOP               ; $a9 = suffix (stack: plural flag)
    BRz F16_NO_SUFFIX
    ASET 14
    SPUSH
    ASET 13
    SPUSH              ; Stack: plural flag, high, low
    ASET 10
    OS_SYSCALL PT
    ASET 9
    SPOP
    ASET 8
    SPOP
    ASET 10
    SPOP               ; Plural flag
    BRz F16_NL
    ASET 10
    OS_SYSCALL PRINT_S
    JMP F16_NL
    F16_NO_SUFFIX:
    SPOP               ; Plural flag
    F16_NL:
    ASET 8
    OS_SYSCALL NEWLINE
    ASET 8
    OS_SYSCALL_RET

; Text (must stay in one page)
S_FILE_NL:   .stringz "FILE\n"
S_DIR_NL:    .stringz "DIRECTORY\n"
S_YES_NL:    .stringz "YES\n"
S_NO_NL:     .stringz "NO\n"
S_BYTE:      .stringz " BYTE"
S_BYTES_C:   .stringz " BYTES, "
S_UNUSED:    .stringz " UNUSED)\n"
S_SECTOR:    .stringz " SECTOR"
S_NONE:      .stringz "(NONE)"
S_OF32IN:    .stringz " OF 32 IN "
S_OF32LP:    .stringz " OF 32 ("
S_FILE:      .stringz " FILE"
S_COMMA:     .stringz ", "
S_DIRECTOR:  .stringz " DIRECTOR"
S_Y:         .stringz "Y"
S_IES:       .stringz "IES"
S_LPAREN:    .stringz " ("
S_RPAREN_NL: .stringz ")\n"

; ===============================================
;                SEGMENT BOUNDARY
; ===============================================
.padseg 0

; Labels (must stay in one page)
S_NAME:      .stringz "NAME:      "
S_PATH:      .stringz "PATH:      "
S_TYPE:      .stringz "TYPE:      "
S_EXEC:      .stringz "EXEC:      "
S_SIZE:      .stringz "SIZE:      "
S_BLOCKS:    .stringz "BLOCKS:    "
S_FRAGS:     .stringz "FRAGMENTS: "
S_ONDISK:    .stringz "ON DISK:   "
S_META:      .stringz "METADATA:  "
S_DATA:      .stringz "DATA:      "
S_ENTRIES:   .stringz "ENTRIES:   "
S_SECTOR_L:  .stringz "SECTOR:    "
S_ENTRY:     .stringz "ENTRY:     "
