"""Running Apricot OS headlessly in aprsim and typing shell commands into it.

aprsim is a full-screen curses program. A :class:`Session` runs it inside a
pseudo-terminal, switches it to RUN mode, waits for the OS to boot, types the
commands one key at a time, then quits with F1. Everything the OS writes to
port 7 goes to a FIFO, which is read in the background and replayed through
:class:`~test_tools.terminal.Terminal`.

Keys must only be typed while the program is waiting in ``PRTin 2``: the
simulator swallows any other key, and a swallowed space *pauses* it. So the
session waits for the program's response before each key, never for a fixed
time unless it has to:

- after a typed key, until the shell echoes it (at most ``key_delay``);
- after Enter (and the last key of :class:`Keys`), until the next prompt
  (at most the step's wait, by default ``command_wait``);
- during a :class:`Wait`, until the next prompt if one is still due (no
  wait at all otherwise);
- at the start, until the first prompt (at most ``boot_wait``).

A wait that reaches its limit just moves on, so a command that never prints
a prompt (a Y/N question, a fault) costs its full wait.

Example::

    session = Session(tools, build, disks={0: disk})
    result = session.run(["LS", "CD BIN", "PWD"])
    assert result["PWD"] == "/BIN"
    disk_after = result.disks[0]
"""

from __future__ import annotations

import fcntl
import os
import select
import struct
import subprocess
import tempfile
import termios
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, Union

from .assembler import OsBuild
from .config import Tools
from .diskimage import OS_SECTORS, SECTOR_SIZE, DiskImage
from .terminal import Terminal

ENTER = b"\r"
PROMPT = b"\n>"          # the shell's prompt (SHELLMEM_PROMPT)
PROMPT_SETTLE = 0.05     # seconds from the prompt until the shell is reading keys
ECHO_SETTLE = 0.01       # seconds from a key's echo until the shell is reading keys
EXIT_WAIT = 5.0          # seconds to wait for the simulator to exit after F1

# What ends a stroke's wait early (see the module docstring)
UNTIL_ECHO = "echo"          # any new terminal output
UNTIL_PROMPT = "prompt"      # the next prompt
UNTIL_PENDING = "pending"    # the next prompt, if one is still due; else wait the full time
F1 = b"\x1bOP"
DELETE = b"\x7f"


@dataclass(frozen=True)
class Type:
    """Type ``text``, then press Enter and wait ``wait`` seconds (default: the session's)."""

    text: str
    wait: float | None = None


@dataclass(frozen=True)
class Keys:
    """Type ``text`` without pressing Enter (for example, a Y/N answer)."""

    text: str
    wait: float | None = None


@dataclass(frozen=True)
class Wait:
    """Wait up to ``seconds`` more for the last command's prompt, for example while a long command runs.

    If the prompt has already arrived, it doesn't wait at all.
    """

    seconds: float


Step = Union[str, Type, Keys, Wait]


@dataclass
class CommandOutput:
    """What the shell printed in response to one typed command.

    ``command`` is the command as the shell echoed it. The shell runs
    commands uppercased but echoes lowercase letters as typed.
    """

    command: str
    lines: list[str]

    @property
    def text(self) -> str:
        """The output as one string, without the blank line before the next prompt."""
        lines = list(self.lines)
        while lines and not lines[-1]:
            lines.pop()
        return "\n".join(lines)


@dataclass
class SessionResult:
    """Everything a session produced."""

    raw: bytes
    terminal: Terminal
    boot_text: str
    outputs: list[CommandOutput]
    disks: dict[int, DiskImage]
    simulator_status: str

    def __getitem__(self, key: int | str) -> str:
        """The output of a command, by position or by its text (first match)."""
        return self.output(key).text

    def output(self, key: int | str) -> CommandOutput:
        if isinstance(key, int):
            return self.outputs[key]
        for output in self.outputs:
            if output.command.upper() == key.upper():
                return output
        commands = [o.command for o in self.outputs]
        raise KeyError(f"no output for {key!r}; the shell answered {commands}")

    def all(self, command: str) -> list[str]:
        """The outputs of every run of ``command``, in order."""
        return [o.text for o in self.outputs if o.command.upper() == command.upper()]

    @property
    def anomalies(self) -> list[str]:
        return [str(a) for a in self.terminal.anomalies]


@dataclass
class Session:
    """One run of the simulator.

    ``disks`` maps disk numbers (0-8) to images; disk 0 is booted. The OS
    image in disk 0's track 0 (sectors 0-61) is always replaced by
    ``build``'s, so a disk prepared earlier boots the current OS.
    ``programs`` are extra PB files loaded into memory before the boot. They
    must be below 0x8000: aprsim stores the load origin in a signed 16-bit
    variable, so higher origins are written out of bounds.
    """

    tools: Tools
    build: OsBuild
    disks: dict[int, DiskImage] = field(default_factory=dict)
    programs: list[bytes] = field(default_factory=list)
    boot_wait: float = 6.0
    key_delay: float = 0.2
    command_wait: float = 1.5
    workdir: Path | None = None

    def run(self, steps: Iterable[Step]) -> SessionResult:
        steps = [Type(s) if isinstance(s, str) else s for s in steps]
        if self.workdir is not None:
            self.workdir.mkdir(parents=True, exist_ok=True)
            return self._run_in(self.workdir, steps)
        with tempfile.TemporaryDirectory(prefix="apricot-session-") as scratch:
            return self._run_in(Path(scratch), steps)

    # ---------------------------------------------------------------- setup

    def _run_in(self, directory: Path, steps: list[Step]) -> SessionResult:
        for stale in directory.glob("*.dsk"):
            stale.unlink()
        (directory / "boot.bin").write_bytes(self.build.boot_image)
        disks = dict(self.disks) or {0: DiskImage(self.build.disk_image)}
        for number, image in disks.items():
            image = image.copy()
            if number == 0:
                image.data[:OS_SECTORS * SECTOR_SIZE] = self.build.disk_image[:OS_SECTORS * SECTOR_SIZE]
            image.save(directory / f"{number}.dsk")
        program_files = []
        for index, program in enumerate(self.programs):
            if program[5] >= 0x80:
                raise ValueError("aprsim cannot load programs at or above 0x8000")
            path = directory / f"program{index}.bin"
            path.write_bytes(program)
            program_files.append(path.name)

        fifo = directory / "tty.fifo"
        if fifo.exists():
            fifo.unlink()
        os.mkfifo(fifo)
        # Opening the read end non-blocking succeeds at once, and lets aprsim's
        # (blocking) open of the write end complete. Holding a write end open
        # ourselves stops the FIFO reporting end-of-file while aprsim isn't
        # connected, which would make select() spin.
        fifo_fd = os.open(fifo, os.O_RDONLY | os.O_NONBLOCK)
        keep_open = os.open(fifo, os.O_WRONLY | os.O_NONBLOCK)
        captured = bytearray()
        try:
            status = _drive(
                [self.tools.simulator, "-f", fifo.name, "boot.bin", *program_files],
                directory, self._keystrokes(steps), fifo_fd, captured)
        finally:
            os.close(keep_open)
            os.close(fifo_fd)

        terminal = Terminal.from_bytes(bytes(captured))
        boot_text, outputs = _split_outputs(terminal.text, steps)
        return SessionResult(
            raw=bytes(captured), terminal=terminal, boot_text=boot_text, outputs=outputs,
            disks={n: DiskImage.load(directory / f"{n}.dsk") for n in disks},
            simulator_status=status)

    def _keystrokes(self, steps: list[Step]) -> list[tuple[bytes, float, str | None]]:
        """The (bytes to type, longest wait afterwards, what ends the wait early) sequence.

        It starts by switching to RUN mode and running ("m", "m", space), and
        ends with F1.
        """
        strokes = [(b"mm ", self.boot_wait, UNTIL_PROMPT)]
        for step in steps:
            if isinstance(step, Wait):
                strokes.append((b"", step.seconds, UNTIL_PENDING))
                continue
            data = step.text.encode("latin-1")
            strokes += [(data[i:i + 1], self.key_delay, UNTIL_ECHO) for i in range(len(data))]
            wait = self.command_wait if step.wait is None else step.wait
            if isinstance(step, Type):
                strokes.append((ENTER, wait, UNTIL_PROMPT))
            elif data:
                strokes[-1] = (strokes[-1][0], wait, UNTIL_PROMPT)
        strokes.append((F1, 0.0, None))
        return strokes


# --------------------------------------------------------------- internals

def _drive(command: list[str], cwd: Path, strokes: list[tuple[bytes, float, str | None]],
           fifo_fd: int, captured: bytearray) -> str:
    """Run ``command`` in a pseudo-terminal, typing ``strokes``. Returns how it ended.

    Terminal output from the program arrives on ``fifo_fd`` and is appended
    to ``captured``.
    """
    # subprocess forks and execs in C, which is safe in a multi-threaded
    # process (pytest-xdist workers are); pty.fork() runs Python in the child.
    fd, terminal = os.openpty()
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
    try:
        simulator = subprocess.Popen(command, cwd=cwd, env={**os.environ, "TERM": "xterm"},
                                     stdin=terminal, stdout=terminal, stderr=terminal,
                                     start_new_session=True)
    finally:
        os.close(terminal)
    try:
        return _type_strokes(simulator, fd, strokes, fifo_fd, captured)
    finally:
        if simulator.poll() is None:            # only if typing failed part way
            simulator.kill()
            simulator.wait()
        os.close(fd)


def _type_strokes(simulator: subprocess.Popen, fd: int, strokes: list[tuple[bytes, float, str | None]],
                  fifo_fd: int, captured: bytearray) -> str:
    """Type ``strokes`` into the simulator on terminal ``fd``, then wait for it to exit. Returns how it ended."""
    alive = _wait_for_screen(fd, fifo_fd, captured, 2.0)
    prompt_due_from = None          # where to look for a prompt that is still due
    for data, wait, until in strokes:
        if not alive:
            break
        start = len(captured)
        if data:
            try:
                os.write(fd, data)
            except OSError:
                break
        if until == UNTIL_PROMPT:
            prompt_due_from = start
        if until == UNTIL_ECHO:
            alive, _ = _drain(fd, fifo_fd, captured, wait, start, b"", ECHO_SETTLE)
        elif until in (UNTIL_PROMPT, UNTIL_PENDING) and prompt_due_from is not None:
            alive, found = _drain(fd, fifo_fd, captured, wait, prompt_due_from, PROMPT, PROMPT_SETTLE)
            if found:
                prompt_due_from = None
        elif until == UNTIL_PENDING:
            pass                    # the prompt has already arrived
        else:
            alive, _ = _drain(fd, fifo_fd, captured, wait)

    deadline = time.time() + EXIT_WAIT
    while simulator.poll() is None and time.time() < deadline:
        _drain(fd, fifo_fd, captured, 0.02)
    _read_available(fifo_fd, captured)
    if simulator.returncode is None:
        simulator.kill()
        simulator.wait()
        return "still running at the end (killed)"
    if simulator.returncode < 0:
        return f"killed by signal {-simulator.returncode}"
    return f"exited with code {simulator.returncode}"


def _wait_for_screen(fd: int, fifo_fd: int, captured: bytearray, seconds: float) -> bool:
    """Wait (at most ``seconds``) until the simulator has drawn its screen, so it reads keys.

    Returns False once the simulator has gone away.
    """
    end = time.time() + seconds
    while time.time() < end:
        ready = select.select([fd, fifo_fd], [], [], 0.05)[0]
        if fifo_fd in ready:
            _read_available(fifo_fd, captured)
        if fd in ready:
            try:
                if not os.read(fd, 65536):
                    return False
            except OSError:
                return False
            break
    return _drain(fd, fifo_fd, captured, 0.1)[0]


def _drain(fd: int, fifo_fd: int, captured: bytearray, seconds: float,
           start: int = 0, until: bytes | None = None, settle: float = 0.0) -> tuple[bool, bool]:
    """For ``seconds``, discard the simulator's screen output and collect terminal output.

    If ``until`` is given, stop ``settle`` seconds after ``captured[start:]``
    contains it (``b""``: as soon as there is any output after ``start``).
    Returns (False once the simulator has gone away, whether ``until`` was found).
    """
    end = time.time() + seconds
    found = False

    def check() -> None:
        nonlocal end, found
        if until is not None and not found and len(captured) > start and until in captured[start:]:
            found = True
            end = min(end, time.time() + settle)

    check()
    while time.time() < end:
        ready = select.select([fd, fifo_fd], [], [], min(0.05, max(0.0, end - time.time())))[0]
        if fifo_fd in ready:
            _read_available(fifo_fd, captured)
            check()
        if fd in ready:
            try:
                if not os.read(fd, 65536):
                    return False, found
            except OSError:
                return False, found
    return True, found


def _read_available(fifo_fd: int, captured: bytearray) -> None:
    """Append whatever is waiting in the FIFO to ``captured``."""
    while True:
        try:
            chunk = os.read(fifo_fd, 65536)
        except BlockingIOError:
            return
        if not chunk:
            return
        captured.extend(chunk)


def _split_outputs(text: str, steps: list[Step]) -> tuple[str, list[CommandOutput]]:
    """Split the logical terminal text into the boot text and one output per command.

    Every command typed with Enter is answered by a new prompt line (``>``
    followed by the echoed command). A command's output is everything between
    its prompt line and the next one.
    """
    lines = text.split("\n")
    prompts = [i for i, line in enumerate(lines) if line.startswith(">")]
    typed = [s for s in steps if isinstance(s, Type)]
    boot_text = "\n".join(lines[:prompts[0]]) if prompts else text
    outputs = []
    for number, index in enumerate(prompts[:len(typed)]):
        end = prompts[number + 1] if number + 1 < len(prompts) else len(lines)
        echoed = lines[index][1:]
        outputs.append(CommandOutput(echoed, lines[index + 1:end]))
    return boot_text, outputs
