# The `test_tools` package

The Python tooling behind the Apricot OS tests. It builds the OS, prepares disk images, boots the OS headlessly in the simulator, and turns what the OS printed and wrote back into things a test can assert on. The tests in `tests/` use it through the fixtures in `conftest.py`; it can also be used from the command line or imported directly.

Nothing here depends on anything outside this repository except three tools: `apricosasm.jar` in the repository root, the `aprsim` simulator, and the `apricosfsman` fs-manager binary (see `config`).

## Modules

| Module | What it does |
|---|---|
| [`config`](#config) | Finds the assembler, the simulator and fs-manager |
| [`assembler`](#assembler) | Builds the OS from a copy of `src/` and checks the result; assembles test programs |
| [`fsmanager`](#fsmanager) | Drives fs-manager to create populated test disks |
| [`diskimage`](#diskimage) | Reads, edits and validates disk images |
| [`simulator`](#simulator) | Boots the OS in `aprsim`, types commands, and splits the output per command |
| [`terminal`](#terminal) | A headless model of `apricosterm`: port-7 bytes in, screen and text out |
| [`programs`](#programs) | Assembles the library test programs and parses their output |
| [`expectations`](#expectations) | Computes what commands such as `STAT` should print, from a disk image |
| [`__main__`](#command-line-use) | The command-line interface |

The most used names are re-exported from the package: `Tools`, `MissingTool`, `OsBuild`, `build_os`, `AssemblyError`, `DiskImage`, `FsManager`, `FsManagerError`, `Session`, `SessionResult`, `Type`, `Keys`, `Wait` and `Terminal`.

### `config`

`Tools` holds where the external tools are. Each tool can be given explicitly, otherwise an environment variable is used, otherwise a default:

| Property | Explicit field | Variable | Default |
|---|---|---|---|
| `tools.simulator` | `aprsim` | `APRSIM` | `aprsim` on the `PATH` |
| `tools.fs_manager` | `fsman` | `APRICOSFSMAN` | `apricosfsman` on the `PATH` |
| `tools.assembler_jar` | `jar` | `APRICOSASM_JAR` | `apricosasm.jar` in the repository root |
| `tools.java` | `java_launcher` | `JAVA` | `java` on the `PATH` |

The simulator and fs-manager accept either a binary name, which is looked up on the `PATH`, or a path to a binary. `Tools.from_environment(aprsim=..., fsman=...)` is what the pytest `--aprsim` and `--fsman` flags feed. Each property is resolved on first use and raises `MissingTool` with a message naming the flag and variable if the tool can't be found; the fixtures turn that into a skip. The simulator is also checked for the `-f` option, which the TTY and port emulation build provides.

The module also defines the repository paths: `OS_REPO`, `OS_SOURCES` (`src/`), `ASSEMBLE_SCRIPT`, `ASSEMBLER_JAR`, `TESTS_DIR` and `PROGRAMS_DIR`.

### `assembler`

`build_os(tools, destination, overrides=None)` copies `src/` to `destination` and assembles it the way `assemble.sh` does: `boot.asm` with `-sh`, then the unit list read from `assemble.sh` with `-ldsh`. `overrides` replaces source files in the copy, for example `{"testprogram.asm": Path("my_test.asm")}`. The result is an `OsBuild` with:

- `boot_image` and `disk_image`: the bytes of `boot.bin` and `link.bin`;
- `units`: one `Unit` per source file, with its `segment`, `size` in bytes and `budget` (the room before the next unit's segment, or before segment 62, the first segment not loaded at boot); `unit.overflows` says if it is over;
- `symbols`: label to addresses, from `symbols.sym`; `build.address("label")` for a unique one;
- `problems`: a list of messages for everything that makes the build unsafe to run.

Three checks run on every build, because the assembler doesn't report them:

- **segment overflow**: a unit larger than its budget;
- **page-end branches**: an immediate branch whose opcode sits at offset `0xFE` or `0xFF` of a page, which lands in the next page (`find_page_end_branches`);
- **cross-page local calls**: `OS_LOCALSYSCALL` and `OS_CALLFUNC_LOCAL` only set the low byte of the target, so the callee must be in the caller's page (`find_cross_page_local_calls`).

`build.assemble_program(source, *support)` assembles a standalone program against the build's sources and returns its PB-format bytes; the same page checks apply and raise `AssemblyError`. `read_pb(data)` splits a PB file into its origin and its bytes. `AssemblyError` is raised for any assembler error.

### `fsmanager`

`FsManager(binary)` drives the fs-manager binary over standard input; `FsManager.from_tools(tools)` uses the configured one.

- `create_disk(base, commands, volume="APRICOT")` formats a disk, runs the commands (`mkdir`, `cd`, `touch`, `loadfile NAME HOSTFILE`, `toggleexec`, ...) and returns a `DiskImage`. `base` is the image to start from, normally `os_build.disk_image`: `format` only rewrites the volume information, the bitmap and the root directory, so an OS image stays bootable. With `base=None` a blank data disk is created with `newdisk`.
- `run(image, commands, create=False)` mounts an existing image file, runs the commands, unmounts (which saves) and returns fs-manager's output. Use it to have fs-manager read a disk the OS wrote.

The tests prepare disks with fs-manager rather than with the OS, so the two filesystem implementations check each other. Two fs-manager bugs to work around: `loadfile` into a non-empty file corrupts data, and `savefile` can truncate files. Always `touch` a fresh file and `loadfile` it once.

### `diskimage`

`DiskImage` is a mutable 512 KiB image: 32 tracks of 64 sectors of 256 bytes. Track 0 holds the OS image (sectors 0 to 61), the volume information (sector 62) and the space bitmap (sector 63); the root directory is at track 1, sector 0. The format is in `APRICOS_DEVELOPMENT_GUIDE.md`, Appendix A.

- Storage: `DiskImage()` (all zeros), `DiskImage(bytes)`, `DiskImage.load(path)`, `image.save(path)`, `image.copy()`, and the raw `image.data` bytearray.
- Sectors: `sector(track, sector)` and `write_sector(track, sector, content)`.
- Volume: `has_signature`, `volume_name`, `bootable`.
- Bitmap: `is_allocated`, `set_allocated`, `free_sectors()` (tracks 1 to 31, in first-fit order), `allocated_count`, and `fill_free_space(leave_free=n)`, which marks everything else allocated to set up "disk full" tests.
- Structures: `entries(location)` lists a directory's in-use entries as `Entry` objects (`slot`, `name`, `is_file`, `executable`, `location`); `file_blocks(metadata)` gives a file's size and block list; `read_file(metadata)` its contents.
- `check()` validates the whole filesystem and returns a `CheckReport`: `errors`, `leaks` (allocated sectors nothing refers to), and every `files[path]` (`FileInfo`: entry, size, blocks, data) and `directories[path]` (`DirectoryInfo`). `report.ok` is true when there are no errors; printing the report lists everything. Every referenced sector must be allocated and used once, names must be valid, block lists must match sizes, and block slots must be contiguous.

Locations are `(track, sector)` tuples. The constants (`TRACKS`, `SECTOR_SIZE`, `ROOT`, `MAX_FILE_SIZE`, `IN_USE`, `EXECUTABLE`, `IS_FILE`, ...) are exported for tests that build sectors by hand.

### `simulator`

`Session(tools, build, disks={}, programs=[], boot_wait=6.0, key_delay=0.2, command_wait=1.5, workdir=None)` is one run of the simulator. `session.run(steps)` writes the disks and programs to a working directory, starts `aprsim` in a pseudo-terminal with port-7 output going to a FIFO, switches it to RUN mode, waits for the boot (until the shell's first prompt, or at most `boot_wait` seconds), types the steps, quits with F1, and returns a `SessionResult`. Disk 0 always gets the current build's OS image, so a disk made earlier boots the current code. Programs are PB files loaded into memory before boot.

Steps are:

- a string, or `Type(text, wait=None)`: typed, then Enter, then a pause;
- `Keys(text, wait=None)`: typed without Enter, for prompts such as `FORMAT`'s confirmation;
- `Wait(seconds)`: wait up to `seconds` more for the last command's prompt, for a long-running command (no wait if it has already arrived).

The simulator only passes a key to the OS while the OS is waiting for input; a key that arrives while it is busy is lost, and a lost space pauses the simulator. So the session waits for a response before typing on: each key's echo (at most `key_delay` seconds), and the next prompt after Enter or the last key of `Keys` (at most `command_wait` seconds, or the step's `wait`). A wait that reaches its limit moves on, so a step that never prints a prompt costs its full wait. Raise the limit for a command that runs longer.

`SessionResult` has:

- `result["CMD"]`: the text printed by the first `CMD`; `result[3]`: by the fourth step; `result.all("CMD")`: every run of it; `result.output(key)`: the `CommandOutput` with `command` and `lines`;
- `boot_text`: what was printed before the first prompt;
- `disks[n]`: disk n after the session, as a `DiskImage`;
- `terminal`: the `Terminal` the output was replayed through, and `raw`: the port-7 bytes;
- `anomalies`: terminal protocol mistakes the OS made;
- `simulator_status`: how `aprsim` ended, normally `"exited with code 0"`.

With `workdir` set, the disks stay there after the run (the `run --keep` CLI option).

### `terminal`

`Terminal` is a port of `apricosterm`'s state machine. The OS writes to the terminal through port 7; every byte is a command byte or an argument to the current command (guide section 2.6). `Terminal.from_bytes(data)` or `terminal.feed(chunk)` replays a stream and keeps three views:

- `screen`: the 80 by 30 grid as the terminal would show it, trailing blank rows removed;
- `transcript`: everything that was ever on screen, including lines that scrolled off and screens wiped by a clear (marked with `CLEAR_MARKER`);
- `text`: the logical text, with no wrapping and with backspaces applied. Match program output against this.

`anomalies` lists things a correct program would never send, such as text arriving while the terminal is not in a print mode, which usually means a stray `03` (end of message) byte. The command codes are exported as constants (`PUTC`, `END_MESSAGE`, `CLEAR_SCREEN`, `REPEAT`, ...).

### `programs`

The library tests run small assembly programs from `tests/programs` that call OS routines directly and print their results as lines of hex bytes, for example `MULT 07 06 2A 00`.

- `assemble_programs(build, names)` assembles `testlib` plus the named programs against the build and checks they don't overlap. It returns `Program` objects by name, with `binary`, `origin`, `end` and `run_command`, the shell command that runs the program.
- `parse_results(text)` splits result lines into `(name, tokens)`; `hex_values(tokens)` converts them; `results_named(text, "MULT")` gives the values of every `MULT` line.

Programs occupy `0x4000` (`testlib`) to `0x5FFF`, with scratch RAM at `0x7000` to `0x73FF`.

### `expectations`

Independent calculations of what OS commands should print, from a `DiskImage`, so the OS is checked against the image rather than against itself. `expected_stat(disk, parent_path, parent, name)` builds `STAT`'s output for an entry, and `block_ranges(blocks)` formats block lists the way `STAT` does, with runs of consecutive sectors shown as `first-last`.

## Command-line use

Run from `tests/`:

```sh
python -m test_tools build                        # build the OS; show segment use and any problems
python -m test_tools mkdisk my.dsk "mkdir BIN" "touch NOTE" "loadfile NOTE notes.txt"
python -m test_tools mkdisk --blank --volume DATA2 data.dsk "touch HELLO"
python -m test_tools run --disk 0=my.dsk LS "CD BIN" PWD
python -m test_tools run --keep run/ "FORMAT" "@keys:Y" LS    # keep run/0.dsk and run/tty.out
python -m test_tools run --program prog.bin "MEMEXEC 4000"    # preload a PB file
python -m test_tools check run/0.dsk --contents   # validate a disk and list its files
python -m test_tools render run/tty.out           # show captured terminal output
```

| Subcommand | Does |
|---|---|
| `build [--out DIR]` | Builds the OS and prints each unit's segments, size and room; exits 1 on any problem |
| `run [--disk N=IMAGE] [--program BIN] [--keep DIR] [--wait S] STEPS...` | Boots the OS and types the steps; prints the transcript. `"@keys:Y"` types without Enter, `"@wait:30"` pauses |
| `mkdisk [--blank] [--volume NAME] IMAGE COMMANDS...` | Creates a formatted disk with fs-manager, bootable unless `--blank` |
| `check [--contents] IMAGE` | Validates a disk and lists its files and directories; exits 1 if invalid |
| `render [--screen] CAPTURE` | Renders captured port-7 output as a transcript, or only the final screen |

`--aprsim NAME-OR-PATH` and `--fsman NAME-OR-PATH`, given before the subcommand, choose the simulator and fs-manager, as the pytest flags do.
