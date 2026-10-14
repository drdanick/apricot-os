"""A headless model of apricosterm, the Apricos terminal.

The OS writes to the terminal through port 7. Every byte is either a command
byte or an argument to the current command (see APRICOS_DEVELOPMENT_GUIDE.md
section 2.6). This module replays such a byte stream and keeps three views of
the result:

* ``screen``: the 80x30 character grid as apricosterm would show it.
* ``history``: lines that scrolled off the top, plus screens wiped by a
  clear-screen command, so nothing printed is lost.
* ``text``: the *logical* text, with no line wrapping and with backspaces
  applied. Use this to match what a program printed.

It also records protocol anomalies, such as text arriving while the terminal
is not in a character-printing mode, which usually means a program sent a
stray ``03`` (end of message) byte.

The state machine is a port of ``apricosterm/src/terminalemulator.c``, and the
cursor rules follow ``terminalrenderer.c``.
"""

from __future__ import annotations

from dataclasses import dataclass, field

ROWS = 30
COLUMNS = 80

# Command bytes
PUTC = 0x00          # print with wrap-around
PUTC_CLIP = 0x01     # print, without wrapping at the end of a line
PUTC_FIXED = 0x02    # print without moving the cursor
END_MESSAGE = 0x03
MOVE_LEFT, MOVE_LEFT_CLIP = 0x04, 0x05
MOVE_RIGHT, MOVE_RIGHT_CLIP = 0x06, 0x07
MOVE_UP, MOVE_UP_CLIP = 0x08, 0x09
MOVE_DOWN, MOVE_DOWN_CLIP = 0x0A, 0x0B
SET_FOREGROUND, SET_BACKGROUND = 0x0C, 0x0D
SET_ROW, SET_COLUMN = 0x0E, 0x0F
CURSOR_VISIBLE = 0x10
SCROLL = 0x11
CLEAR_SCREEN = 0x12
REPEAT = 0x7F

KNOWN_COMMANDS = set(range(0x00, 0x13)) | {REPEAT}
PRINT_COMMANDS = {PUTC, PUTC_CLIP, PUTC_FIXED}

#: Marker inserted into ``text`` and ``history`` where the screen was cleared.
CLEAR_MARKER = "----- CLS -----"


@dataclass
class Anomaly:
    """Something in the byte stream that a correct program would not send."""

    offset: int
    message: str

    def __str__(self) -> str:
        return f"byte {self.offset:#x}: {self.message}"


@dataclass
class Terminal:
    """Replays a port-7 byte stream. Feed bytes with :meth:`feed`."""

    grid: list[list[str]] = field(default_factory=lambda: _blank_grid())
    row: int = 0
    column: int = 0
    history: list[str] = field(default_factory=list)
    anomalies: list[Anomaly] = field(default_factory=list)
    _text: list[str] = field(default_factory=list)
    _command: int = 0xFF
    _repeat: bool = False
    _idle: bool = True
    _offset: int = 0

    # ------------------------------------------------------------------ input

    def feed(self, data: bytes) -> "Terminal":
        """Process a chunk of port-7 output. Returns ``self`` for chaining."""
        for byte in data:
            self._byte(byte)
            self._offset += 1
        return self

    @classmethod
    def from_bytes(cls, data: bytes) -> "Terminal":
        return cls().feed(data)

    # ----------------------------------------------------------------- output

    @property
    def screen(self) -> list[str]:
        """The visible screen, one string per row, trailing blank rows removed."""
        lines = ["".join(row).rstrip() for row in self.grid]
        while lines and not lines[-1]:
            lines.pop()
        return lines

    @property
    def transcript(self) -> list[str]:
        """Everything that was ever on screen, oldest first."""
        return [line.rstrip() for line in self.history] + self.screen

    @property
    def text(self) -> str:
        """The logical text that was printed: no wrapping, backspaces applied."""
        return "".join(self._text)

    @property
    def in_print_mode(self) -> bool:
        """True if the terminal is in repeat mode on a print command (``7F 00``)."""
        return self._repeat and not self._idle and self._command in PRINT_COMMANDS

    # -------------------------------------------------------------- internals

    def _byte(self, byte: int) -> None:
        if self._idle:
            self._command = byte
            if byte not in KNOWN_COMMANDS:
                hint = f" ('{chr(byte)}': text sent outside print mode?)" if 0x20 <= byte < 0x7F else ""
                self._anomaly(f"unknown command byte {byte:#04x} while idle{hint}")
            if byte == REPEAT:
                self._repeat = True
            elif byte != END_MESSAGE:
                self._idle = False
            return

        if byte == END_MESSAGE and self._repeat:
            self._repeat = False
        else:
            self._argument(self._command, byte)
            if self._repeat and self._command not in PRINT_COMMANDS and 0x20 <= byte < 0x7F:
                self._anomaly(f"'{chr(byte)}' consumed as an argument of command {self._command:#04x}")

        if not self._repeat:
            self._idle = True

    def _argument(self, command: int, byte: int) -> None:
        if command == PUTC:
            self._character(byte, move=True, wrap=True)
        elif command == PUTC_CLIP:
            self._character(byte, move=True, wrap=False)
        elif command == PUTC_FIXED:
            self._character(byte, move=False, wrap=False)
        elif command in (MOVE_LEFT, MOVE_LEFT_CLIP):
            self._left(clamp=command == MOVE_LEFT_CLIP)
        elif command in (MOVE_RIGHT, MOVE_RIGHT_CLIP):
            self._right(clamp=command == MOVE_RIGHT_CLIP)
        elif command in (MOVE_UP, MOVE_UP_CLIP):
            self._up(clamp=command == MOVE_UP_CLIP)
        elif command in (MOVE_DOWN, MOVE_DOWN_CLIP):
            self._down(clamp=command == MOVE_DOWN_CLIP)
        elif command == SET_ROW:
            self.row = byte
        elif command == SET_COLUMN:
            self.column = byte
        elif command == SCROLL:
            self._scroll(byte, move_cursor=True)
        elif command == CLEAR_SCREEN:
            self._clear()
        # Colours, cursor visibility and unknown commands change nothing we model.

    def _character(self, byte: int, move: bool, wrap: bool) -> None:
        if byte == 0x08:                      # backspace
            if move:
                self._backspace()
            else:
                self._put(" ", move=False, wrap=False)
            if self._text and self._text[-1] != "\n":
                self._text.pop()
        elif byte == 0x0A:                    # newline
            self._newline()
            self._text.append("\n")
        elif byte == 0x0D:                    # carriage return
            self.column = 0
        else:
            if not 0x20 <= byte < 0x7F:
                self._anomaly(f"non-printable byte {byte:#04x} drawn as a glyph")
            char = chr(byte) if 0x20 <= byte < 0x7F else "·"
            self._put(char, move=move, wrap=wrap)
            self._text.append(char)

    def _anomaly(self, message: str) -> None:
        self.anomalies.append(Anomaly(self._offset, message))

    # Cursor and screen operations (terminalrenderer.c)

    def _put(self, char: str, move: bool, wrap: bool) -> None:
        if 0 <= self.row < ROWS and 0 <= self.column < COLUMNS:
            self.grid[self.row][self.column] = char
        if move:
            self._right(clamp=not wrap)

    def _newline(self) -> None:
        self.row += 1
        self.column = 0
        if self.row >= ROWS:
            self.row -= 1
            self._scroll(1, move_cursor=False)

    def _backspace(self) -> None:
        self.column -= 1
        if self.column < 0:
            self.column = 0
            self.row -= 1
            if self.row < 0:
                self.row = 0
            else:
                self.column = COLUMNS - 1
        self._put(" ", move=False, wrap=True)

    def _left(self, clamp: bool) -> None:
        self.column -= 1
        if self.column < 0:
            self.column = 0 if clamp else COLUMNS - 1

    def _right(self, clamp: bool) -> None:
        self.column += 1
        if self.column >= COLUMNS:
            if clamp:
                self.column = COLUMNS - 1
            else:
                self.column = 0
                self.row += 1
        if self.row >= ROWS:
            self._scroll(1, move_cursor=False)
            self.row -= 1

    def _up(self, clamp: bool) -> None:
        self.row -= 1
        if self.row < 0:
            self.row = 0 if clamp else ROWS - 1

    def _down(self, clamp: bool) -> None:
        self.row += 1
        if self.row >= ROWS:
            self.row = ROWS - 1 if clamp else 0

    def _scroll(self, lines: int, move_cursor: bool) -> None:
        lines = min(lines, ROWS)
        for _ in range(lines):
            self.history.append("".join(self.grid.pop(0)))
            self.grid.append([" "] * COLUMNS)
        if move_cursor:
            for _ in range(lines):
                self._up(clamp=True)

    def _clear(self) -> None:
        self.history.extend(self.screen)
        self.history.append(CLEAR_MARKER)
        self._text.append(f"\n{CLEAR_MARKER}\n")
        self.grid = _blank_grid()
        self.row = self.column = 0


def _blank_grid() -> list[list[str]]:
    return [[" "] * COLUMNS for _ in range(ROWS)]
