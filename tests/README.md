# Apricot OS tests

An automated test suite for Apricot OS. It builds the OS from `src/`, boots it in the Apricos simulator without a window, types shell commands, and checks what the OS printed and what it wrote to its disks.

The suite covers:

| Area | Tests |
|---|---|
| The build | segment budgets, page-end branches, cross-page local calls, image layout (`test_build.py`) |
| The stage 1 boot loader | no disk, bad signatures, bad boot flags; `DISKSTAT`'s boot flag check (`test_boot.py`) |
| Boot and the shell | boot messages, every built-in command, line editing, the 128-character limit (`test_shell.py`) |
| Filesystem | `LS`, `CD`, `PWD` (`test_fs_navigation.py`); `CAT`, `STAT` (`test_fs_read.py`); `TOUCH`, `MKDIR`, `WRITE` (`test_fs_write.py`); `RM`, `MV`, `CP`, size limits, disk full (`test_fs_modify.py`) |
| Disks and formatting | `DISKSEL`, `DISKSTAT`, `FSSTAT` with several disks (`test_disks.py`); `FORMAT` and running without a filesystem (`test_format.py`) |
| Libraries | `memutil`, `libmath`, `libdisp`, `osutil`, `diskio`, `diskalloc`, called directly by test programs (`test_library.py`) |
| Faults | bad disk I/O and runaway code (`test_faults.py`) |
| The tools themselves | `test_tooling.py`, `test_cli.py` |

Known OS bugs have tests marked as expected failures (`xfail(strict=True)`), with the bug described in the reason. When a bug is fixed, its test starts passing, which pytest reports as a failure until the mark is removed.

## Running the tests

You need:
- Python 3.10 or newer, and `tox` (or `pytest`);
- Java, and `apricosasm.jar` in the root of this repository (where `assemble.sh` expects it);
- `aprsim`, the simulator, built with TTY and port emulation (`aprsim -h` lists `-f`);
- `apricosfsman`, the apricos-fs-manager binary, which prepares the test disks.

Nothing else outside this repository is used. The simulator and fs-manager are each given as a binary name, looked up on the `PATH` (a system install), or as a path to a binary (handy while iterating on a fresh build):

| Tool | pytest flag | Environment variable | Default |
|---|---|---|---|
| Simulator | `--aprsim NAME-OR-PATH` | `APRSIM` | `aprsim` on the `PATH` |
| fs-manager | `--fsman NAME-OR-PATH` | `APRICOSFSMAN` | `apricosfsman` on the `PATH` |
| Assembler | | `APRICOSASM_JAR` | `apricosasm.jar` in the repository root |
| Java | | `JAVA` | `java` on the `PATH` |

The flag wins over the variable. Write a path as `--fsman=PATH` (with `=`): given as a separate word, pytest takes an existing path for a test directory before it reads the options. If a tool can't be found, the tests that need it are skipped and the reason is shown.

From `apricot-os/tests`:

```sh
tox                      # everything (several minutes)
tox -e fast              # only the tests that don't boot the OS (seconds)
tox -- -k test_cat       # pass options through to pytest
pytest test_shell.py     # or run pytest directly
pytest --aprsim=~/dev/apricosim-curses/build/aprsim --fsman=~/dev/apricos-fs-manager/build/src/apricosfsman
```

The same `--aprsim` and `--fsman` flags work with `python -m test_tools` (before the subcommand).

### Things that affect timing

The simulator only passes a key to the OS while the OS is waiting for input. A key that arrives while it's busy is lost, and a lost space pauses the simulator. So the harness waits for the OS's response before typing on: each key's echo (at most `key_delay`, 0.2 s), the next prompt after a command (at most `command_wait`, 1.5 s, or the step's own wait), and the first prompt after booting (at most `boot_wait`, 6 s). A wait that reaches its limit just moves on, so a command that never prints a prompt (a Y/N question, a fault) costs its full wait. If output is cut short because a command takes longer than its limit, give that step a longer wait (`Type("CP A B", wait=10)`) or follow it with `Wait(seconds)`.

## Layout

```
tests/
    README.md
    tox.ini                 test environments and pytest settings
    conftest.py             shared fixtures (build, disks, booting)
    test_*.py               the tests
    test_tools/             the test tooling, a Python package (see its README)
    programs/               assembly test programs for the library tests
```

### The `test_tools` package

The tooling is documented module by module in [`test_tools/README.md`](test_tools/README.md).

### Using the tools by hand

The same tools are available from the command line (run from `tests/`):

```sh
python -m test_tools build                        # build the OS; show segment use and any problems
python -m test_tools mkdisk my.dsk "mkdir BIN" "touch NOTE" "loadfile NOTE notes.txt"
python -m test_tools run --disk 0=my.dsk LS "CD BIN" PWD
python -m test_tools run --keep run/ "FORMAT" "@keys:Y" LS    # keep run/0.dsk and run/tty.out
python -m test_tools check run/0.dsk --contents   # validate a disk and list its files
python -m test_tools render run/tty.out           # show captured terminal output
```

In `run`, `"@keys:Y"` types without pressing Enter (for prompts), and `"@wait:30"` pauses. The OS on disk 0 is always replaced by the current build, so a disk made earlier boots the current code.

## Writing tests

A typical test module boots once and checks each command separately:

```python
import pytest

pytestmark = pytest.mark.simulator        # boots the OS; excluded by `tox -e fast`


@pytest.fixture(scope="module")
def session(boot, make_disk, host_files):
    disk = make_disk("mkdir BIN", "touch NOTE", f"loadfile NOTE {host_files['hello']}")
    return boot(["LS", "CAT NOTE", "CD BIN", "PWD"], disks={0: disk})


def test_ls(session):
    assert session["LS"].splitlines() == ["BIN/", "NOTE"]


def test_disk_after(session):
    assert session.disks[0].check().ok
```

| Fixture | What it gives you |
|---|---|
| `boot(steps, disks=..., programs=..., command_wait=...)` | Runs a session and returns a `SessionResult` |
| `make_disk(*fs_manager_commands, volume=..., blank=False)` | A formatted disk; bootable unless `blank=True` |
| `host_files` | Paths of sample files for `loadfile` |
| `os_build` | The build, including `units`, `symbols` and `problems` |
| `library_programs` | The assembled test programs |

`steps` are strings (typed, then Enter), `Keys("Y")` (typed without Enter), or `Wait(seconds)` (wait up to that long for the last command's prompt).

On a `SessionResult`:
- **`session["CMD"]`** is the output of the first `CMD`;
- **`session[3]`** is the output of the fourth command;
- **`session.all("CMD")`** lists the output of every `CMD`;
- **`session.disks[n]`** is disk n after the session;
- **`session.anomalies`** lists terminal protocol mistakes;
- **`session.boot_text`** is what was printed before the first prompt.

### Test programs

`programs/*.asm` are small programs that call OS routines directly and print the results as hex, e.g. `MULT 07 06 2A 00`. They are assembled against the current OS and loaded into memory above the OS (0x4000–0x5FFF) before it boots. They share:
- **`testlib.asm`,** which prints hex;
- **`testmacros.asm`,** with macros such as `TM_SET`, `TM_PREG` and `TM_LABEL`.

Scratch RAM for the programs is 0x7000–0x73FF. The simulator can't load programs at 0x8000 or above, because its loader stores the origin in a signed 16-bit variable.

To add a program:
1. Give it a free `#segment` in that range. The tests check that programs don't overlap.
2. Add its name to `LIBRARY_PROGRAMS` in `conftest.py`.
3. Run it from a test with `library_programs["name"].run_command`.
