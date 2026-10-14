Shell commands
==============

The Apricot OS shell reads one line at a time (up to 128 characters) and converts it to uppercase. The first word is the command; everything after the first space is its argument. If the shell doesn't recognise the command, it prints `BAD COMMAND OR FILENAME`.

| Command | Purpose |
| ------- | ------- |
| [`HELP`](#help) | List the known commands |
| [`ECHO`](#echo-text) | Print text |
| [`CLS`](#cls) | Clear the screen |
| [`MEMEXEC`](#memexec-address) | Run code at a memory address |
| [`DISKSEL`](#disksel-n) | Select a disk |
| [`DISKSTAT`](#diskstat) | Show the selected disk and its volume information |
| [`LS`](#ls) | List the current directory |
| [`CD`](#cd-name--cd---cd-) | Change the current directory |
| [`PWD`](#pwd) | Print the current directory |
| [`CAT`](#cat-name) | Print a file |
| [`STAT`](#stat-name) | Show everything stored about a file or directory |
| [`TOUCH`](#touch-name) | Create an empty file |
| [`MKDIR`](#mkdir-name) | Create an empty directory |
| [`WRITE`](#write-name-text) | Append a line of text to a file |
| [`RM`](#rm-name) | Delete a file or an empty directory |
| [`MV`](#mv-old-new) | Rename a file or directory |
| [`CP`](#cp-src-dst) | Copy a file |
| [`FSSTAT`](#fsstat) | Show the filesystem's status and free space |
| [`FORMAT`](#format-name) | Create an empty filesystem on the selected disk |


General commands
----------------

### `HELP`

Prints `KNOWN COMMANDS:` followed by the shell's commands, one per line.

### `ECHO TEXT`

Prints TEXT back to the shell.

```
>ECHO HELLO WORLD
HELLO WORLD
```

### `CLS`

Clears the screen.

### `MEMEXEC ADDRESS`

Jumps to ADDRESS, given as up to 4 hex digits, and runs the code there. The shell saves all registers first and pushes a return address, so a program that ends with `OS_PROG_EXIT` returns to the shell. The input isn't checked: an address that holds no code runs into empty memory and stops with `FLAGRANT SYSTEM ERROR`.

The sample program in [`src/testprogram.asm`](../src/testprogram.asm) is assembled with the OS at address 0x3D00:

```
>MEMEXEC 3D00
Hello! You have just executed ApricotOS' first program!
```


Disk commands
-------------

The simulator provides up to 9 disks, numbered 0 to 8. Disk N is the file `N.dsk` in the simulator's working directory. The OS boots from disk 0, which is selected at startup.

### `DISKSEL N`

Selects disk N (0–8) and mounts its filesystem. The current directory becomes `/`. If the new disk has no filesystem, the OS prints `NO FILESYSTEM - TYPE FORMAT`, and the filesystem commands report `NO FILESYSTEM` until you run `FORMAT`.

If `N.dsk` doesn't exist, the current disk stays selected and nothing changes.

```
>DISKSEL 2
>LS
HELLO
STUFF/
>DISKSEL 3
ERROR: NO SUCH DISK
```

Errors: `MISSING ARGUMENT`; `NO SUCH DISK` (N isn't a single digit 0–8, or `N.dsk` doesn't exist).

### `DISKSTAT`

Shows the selected disk and the volume information stored on it:

```
>DISKSTAT
DISK:      0
SIGNATURE: VALID
VOLUME:    APRICOT
BOOTABLE:  YES
```

- `SIGNATURE` is `VALID` if the disk has the Apricot disk signature. If it is `INVALID`, nothing else is printed.
- `VOLUME` is the volume name, or `(NONE)` if it is empty.
- `BOOTABLE` is `YES` if the volume information carries the boot signature.

If no disk is selected, it prints `NO DISK`.


Filesystem commands
-------------------

These commands work on the selected disk, relative to the current directory.

### Rules shared by all filesystem commands


**Names** must:

- be 1 to 6 characters long;
- use printable characters only, with no spaces and no `/`;
- not start with `.`.

A name breaking these rules gives `ERROR: BAD NAME`; it is never shortened. A file and a directory in the same directory can't share a name.

**Paths:** only single names in the current directory. `CD` also understands `/` and `..`.

**Limits:**

| What | Limit |
| ---- | ----- |
| Entries per directory | 32 |
| File size | 32,512 bytes (127 sectors of 256 bytes) |
| Directory depth | 15 levels below `/` |
| Command line length | 128 characters |

**Errors** are printed as `ERROR: <message>`:

| Message | Meaning |
| ------- | ------- |
| `NO FILESYSTEM` | The disk has no filesystem; only `FORMAT` works |
| `NOT FOUND` | No entry with that name |
| `ALREADY EXISTS` | The target name is taken |
| `BAD NAME` | The name breaks the rules above |
| `DIRECTORY FULL` | The directory already has 32 entries |
| `DISK FULL` | No free sectors are left |
| `FILE TOO BIG` | The result would exceed 32,512 bytes |
| `NOT A DIRECTORY` | `CD` was given a file |
| `NOT A FILE` | A file command was given a directory |
| `DIRECTORY NOT EMPTY` | `RM` was given a directory with entries in it |
| `PATH TOO DEEP` | `CD` would go past 15 levels |
| `MISSING ARGUMENT` | A required name or text is missing |
| `NO SUCH DISK` | `DISKSEL` was given a disk that doesn't exist |

**No filesystem:** if the boot disk has no filesystem, the OS prints `NO FILESYSTEM - TYPE FORMAT` after the shell's greeting. `DISKSEL` prints the same notice when it selects a disk without one.



### `LS`

Lists the current directory, one entry per line. A directory name is followed by `/` and an executable file by `*`. An empty directory prints nothing. Any argument is ignored.

```
>LS
BIN/
README
TOOL*
```

### `CD NAME` · `CD ..` · `CD /`

Changes the current directory:

- `CD NAME` goes into a subdirectory;
- `CD ..` goes up one level (at `/` it does nothing);
- `CD /` goes to the root.

Errors: `MISSING ARGUMENT`, `BAD NAME`, `NOT FOUND`, `NOT A DIRECTORY`, `PATH TOO DEEP`.

### `PWD`

Prints the current directory, as `/` or `/BIN/SUB`.

```
>CD BIN
>PWD
/BIN
```

### `CAT NAME`

Prints a file. Bytes 0x20–0x7E and newlines are printed as they are; any other byte is shown as `.`, so a binary file can't send commands to the terminal. An empty file prints nothing.

Errors: `MISSING ARGUMENT`, `BAD NAME`, `NOT FOUND`, `NOT A FILE`.

### `STAT NAME`

Shows everything the filesystem stores about a file or directory in the current directory. The filesystem keeps no dates, owners or permissions, so those aren't shown.

For a file:

```
>STAT NOTE
NAME:      NOTE
PATH:      /DOCS/NOTE
TYPE:      FILE
EXEC:      NO
SIZE:      517 BYTES
BLOCKS:    3 (768 BYTES, 251 UNUSED)
FRAGMENTS: 1
ON DISK:   4 SECTORS
METADATA:  1/6
DATA:      1/7-1/9
ENTRY:     2 OF 32 IN /DOCS (1/4)
```

| Field | Meaning |
| ----- | ------- |
| `PATH` | The full path to the entry |
| `EXEC` | Whether the entry's executable flag is set |
| `SIZE` | The file's size in bytes |
| `BLOCKS` | The number of 256-byte data blocks, the space they hold, and how much of it is unused |
| `FRAGMENTS` | The number of separate runs of consecutive sectors the data is stored in (1 = contiguous) |
| `ON DISK` | The sectors used in total: the data blocks plus the file's metadata sector |
| `METADATA` | Where the file's metadata sector is, as `track/sector` |
| `DATA` | Every data block, as `track/sector`, with runs of consecutive sectors shown as ranges (`1/7-1/9`); `(NONE)` for an empty file |
| `ENTRY` | Which of the 32 slots in the parent directory holds the entry, the parent's path, and the parent's sector |

For a directory, the size and block lines are replaced by:

```
>STAT DOCS
NAME:      DOCS
PATH:      /DOCS
TYPE:      DIRECTORY
EXEC:      NO
ENTRIES:   2 OF 32 (1 FILE, 1 DIRECTORY)
SECTOR:    1/4
ENTRY:     3 OF 32 IN / (1/0)
```

`ENTRIES` is how many of the directory's 32 slots are in use, split into files and subdirectories; `SECTOR` is where the directory itself is stored.

Errors: `MISSING ARGUMENT`, `BAD NAME`, `NOT FOUND`.

### `TOUCH NAME`

Creates an empty file.

Errors: `MISSING ARGUMENT`, `BAD NAME`, `ALREADY EXISTS`, `DIRECTORY FULL`, `DISK FULL`.

### `MKDIR NAME`

Creates an empty directory.

Errors: the same as `TOUCH`.

### `WRITE NAME TEXT`

Adds TEXT and a newline to the end of the file NAME, creating the file first if it doesn't exist. Everything after the first space following NAME is the text, including any extra spaces. Each `WRITE` adds one line; repeat it to add more.

```
>WRITE NOTE HELLO
>WRITE NOTE WORLD
>CAT NOTE
HELLO
WORLD
```

If the disk fills up part way through, the bytes that fit are kept and the command reports `DISK FULL`.

Errors:

- `MISSING ARGUMENT`: there is no text after the name;
- `BAD NAME`;
- `NOT A FILE`: NAME is a directory;
- `FILE TOO BIG`: nothing is written;
- `DIRECTORY FULL`, `DISK FULL`.

### `RM NAME`

Deletes a file, freeing all of its sectors, or deletes an **empty** directory.

Errors: `MISSING ARGUMENT`, `BAD NAME`, `NOT FOUND`, `DIRECTORY NOT EMPTY`.

### `MV OLD NEW`

Renames a file or directory within the current directory. It can't move an entry to another directory. The executable bit is kept.

Errors: `MISSING ARGUMENT`, `BAD NAME`, `NOT FOUND`, `ALREADY EXISTS`.

### `CP SRC DST`

Copies a file to a new file in the current directory. Directories can't be copied. The executable bit is kept. If the disk fills up during the copy, everything is undone and nothing is created.

Errors: `MISSING ARGUMENT`, `BAD NAME`, `NOT FOUND`, `NOT A FILE`, `ALREADY EXISTS`, `DIRECTORY FULL`, `DISK FULL`.

Copying a large file is slow: a maximum-size file takes about a minute. Wait for the prompt before typing again, because keys typed while the OS is busy are lost.

### `FSSTAT`

Shows whether the selected disk has a filesystem, and how much of it is used. Sizes cover tracks 1–31, the part of the disk available for files; KB values are rounded down.

```
>FSSTAT
FILESYSTEM: OK
USED:       7 SECTORS (1 KB)
FREE:       1977 SECTORS (494 KB)
TOTAL:      1984 SECTORS (496 KB)
```

If there is no usable filesystem, only the `FILESYSTEM` line is printed:

| Status | Meaning |
| ------ | ------- |
| `NOT FORMATTED` | The disk has a signature but no filesystem; run `FORMAT` |
| `NO SIGNATURE` | The disk is blank or isn't an Apricot disk; run `FORMAT` |
| `NO DISK` | No disk is selected |

### `FORMAT [NAME]`

Erases the selected disk and creates an empty filesystem, then returns to `/`. It asks for confirmation first:

```
>FORMAT DATA
FORMAT DISK 1? (Y/N) Y
```

Press `Y` to go ahead. **Any other key, including Enter, cancels** and prints `CANCELLED`. Only one key is read; you don't need to press Enter after it.

**Every file and directory on the disk is lost.** The OS boot code on the disk is kept.

The volume information is handled as follows:

- **NAME** (optional, up to 8 characters, no spaces) sets the volume name. Without it, the existing name is kept.
- **On a disk with no signature**, such as a blank disk, FORMAT writes the signature and the name (`APRICOT` if no NAME is given). The disk isn't marked bootable.
- **The boot flag** is never changed: a bootable disk stays bootable.

This is the only filesystem command that works on a disk without a filesystem. Use it to set up a blank disk, or a disk image built by `assemble.sh`, which has no filesystem.

Errors: `BAD NAME` (NAME is longer than 8 characters).

Example session
---------------

```
>FORMAT
>MKDIR DOCS
>CD DOCS
>WRITE README HELLO FROM APRICOT OS
>CP README COPY
>MV COPY NOTES
>LS
README
NOTES
>PWD
/DOCS
>CD ..
>RM DOCS
ERROR: DIRECTORY NOT EMPTY
```


See also
--------

- `APRICOS_DEVELOPMENT_GUIDE.md` §5.3 and §5.7, in the workspace root: the filesystem API for programs, status codes and on-disk rules.
- [`os_layout.txt`](../os_layout.txt): where the filesystem code lives in memory.
- `filesystem/filesystem.tex` in the `apricot-os-documentation` project: the on-disk format.
