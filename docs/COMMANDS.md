Shell commands
==============

The Apricot OS shell reads one line at a time (up to 128 characters) and converts it to uppercase. The first word is the command; everything after the first space is its argument. If the shell doesn't recognise the command, it prints `BAD COMMAND OR FILENAME`.

| Command | Purpose |
| ------- | ------- |
| [`HELP`](#help) | List the known commands |
| [`ECHO`](#echo-text) | Print text |
| [`CLS`](#cls) | Clear the screen |
| [`MEMEXEC`](#memexec-address) | Run code at a memory address |
| [`LS`](#ls) | List the current directory |
| [`CD`](#cd-name--cd---cd-) | Change the current directory |
| [`PWD`](#pwd) | Print the current directory |
| [`CAT`](#cat-name) | Print a file |
| [`TOUCH`](#touch-name) | Create an empty file |
| [`MKDIR`](#mkdir-name) | Create an empty directory |
| [`WRITE`](#write-name-text) | Append a line of text to a file |
| [`RM`](#rm-name) | Delete a file or an empty directory |
| [`MV`](#mv-old-new) | Rename a file or directory |
| [`CP`](#cp-src-dst) | Copy a file |
| [`FORMAT`](#format) | Create an empty filesystem on the boot disk |


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


Filesystem commands
-------------------

These commands work on the boot disk (disk 0), relative to the current directory.

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

**No filesystem:** if the boot disk has no filesystem, the OS prints `NO FILESYSTEM - TYPE FORMAT` after the shell's greeting.



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

### `FORMAT`

Erases the boot disk and creates an empty filesystem, then returns to `/`.

**It doesn't ask for confirmation, and every file and directory is lost.** The OS itself and the volume name are kept.

This is the only filesystem command that works on a disk without a filesystem. Use it to set up a disk image built by `assemble.sh`, which has no filesystem.


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
