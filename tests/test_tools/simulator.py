"""Running Apricot OS headlessly in aprsim and typing shell commands into it.

aprsim is a full-screen curses program. A :class:`Session` runs it inside a
pseudo-terminal, switches it to RUN mode, waits for the OS to boot, types the
commands one key at a time, then quits with F1. Everything the OS writes to
port 7 goes to a FIFO, which is read in the background and replayed through
:class:`~test_tools.terminal.Terminal`.

Typing has to be slow: the simulator only passes a key to the program if it
arrives while the program is waiting in ``PRTin 2``; otherwise the key is
swallowed, and a swallowed space *pauses* the simulator. After a long-running
command, add a :class:`Wait`.

Example::

    session = Session(tools, build, disks={0: disk})
    result = session.run(["LS", "CD BIN", "PWD"])
    assert result["PWD"] == "/BIN"
    disk_after = result.disks[0]
"""

from __future__ import annotations

import fcntl
import os
import pty
import select
import signal
import struct
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
    """Do nothing for ``seconds``, for example while a long command runs."""

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
    boot_wait: float = 8.0
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

    def _keystrokes(self, steps: list[Step]) -> list[tuple[bytes, float]]:
        """The (bytes to type, seconds to wait afterwards) sequence for a session."""
        strokes = [(b"m", 0.2), (b"m", 0.2), (b" ", self.boot_wait)]
        for step in steps:
            if isinstance(step, Wait):
                strokes.append((b"", step.seconds))
                continue
            data = step.text.encode("latin-1")
            strokes += [(data[i:i + 1], self.key_delay) for i in range(len(data))]
            wait = self.command_wait if step.wait is None else step.wait
            if isinstance(step, Type):
                strokes.append((ENTER, wait))
            elif strokes:
                strokes[-1] = (strokes[-1][0], wait)
        strokes.append((F1, 1.0))
        return strokes


# --------------------------------------------------------------- internals

def _drive(command: list[str], cwd: Path, strokes: list[tuple[bytes, float]],
           fifo_fd: int, captured: bytearray) -> str:
    """Run ``command`` in a pseudo-terminal, typing ``strokes``. Returns how it ended.

    Terminal output from the program arrives on ``fifo_fd`` and is appended
    to ``captured``.
    """
    pid, fd = pty.fork()
    if pid == 0:                                   # child: become the simulator
        os.chdir(cwd)
        os.environ["TERM"] = "xterm"
        os.execvp(command[0], command)

    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
    alive = _drain(fd, fifo_fd, captured, 0.5)
    for data, wait in strokes:
        if not alive:
            break
        if data:
            try:
                os.write(fd, data)
            except OSError:
                break
        alive = _drain(fd, fifo_fd, captured, wait)
    _drain(fd, fifo_fd, captured, 1.0)

    deadline = time.time() + 3.0
    done, status = os.waitpid(pid, os.WNOHANG)
    while done == 0 and time.time() < deadline:
        time.sleep(0.05)
        done, status = os.waitpid(pid, os.WNOHANG)
    _read_available(fifo_fd, captured)
    if done == 0:
        os.kill(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
        return "still running at the end (killed)"
    if os.WIFSIGNALED(status):
        return f"killed by signal {os.WTERMSIG(status)}"
    return f"exited with code {os.WEXITSTATUS(status)}"


def _drain(fd: int, fifo_fd: int, captured: bytearray, seconds: float) -> bool:
    """For ``seconds``, discard the simulator's screen output and collect terminal output.

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
    return True


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
