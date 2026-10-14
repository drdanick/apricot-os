"""The library test programs in ``tests/programs``.

Each program is assembled at its own ``#segment`` and loaded into memory
before the OS boots (see :class:`~test_tools.simulator.Session`), then run
with ``MEMEXEC``. Programs print their results as lines of hex bytes::

    MULT 07 06 2A 00

:func:`parse_results` turns such output into ``(name, [values])`` pairs.

Memory used: 0x4000 (``testlib``) up to 0x5FFF for programs, and
0x7000-0x73FF as scratch RAM.
"""

from __future__ import annotations

from dataclasses import dataclass

from .assembler import OsBuild, read_pb
from .config import PROGRAMS_DIR

SUPPORT_FILES = ("testlib.asm", "testmacros.asm")


@dataclass(frozen=True)
class Program:
    name: str
    binary: bytes

    @property
    def origin(self) -> int:
        return read_pb(self.binary)[0]

    @property
    def end(self) -> int:
        return self.origin + len(read_pb(self.binary)[1])

    @property
    def run_command(self) -> str:
        """The shell command that runs it."""
        return f"MEMEXEC {self.origin:04X}"


def assemble_programs(build: OsBuild, names: list[str]) -> dict[str, Program]:
    """Assemble ``testlib`` and the named programs, and check they don't overlap."""
    support = [PROGRAMS_DIR / name for name in SUPPORT_FILES]
    programs = {name: Program(name, build.assemble_program(PROGRAMS_DIR / f"{name}.asm", *support))
                for name in ["testlib", *names]}
    spans = sorted(programs.values(), key=lambda p: p.origin)
    for first, second in zip(spans, spans[1:]):
        if first.end > second.origin:
            raise ValueError(f"{first.name} (to {first.end:#06x}) overlaps {second.name} "
                             f"(from {second.origin:#06x}); change a #segment")
    if spans[-1].end > 0x7000:
        raise ValueError(f"{spans[-1].name} runs into the scratch RAM at 0x7000")
    return programs


def parse_results(text: str) -> list[tuple[str, list[str]]]:
    """Split result lines into (name, tokens). Use :func:`hex_values` on the tokens."""
    return [(line.split()[0], line.split()[1:]) for line in text.splitlines() if line.strip()]


def hex_values(tokens: list[str]) -> list[int]:
    return [int(token, 16) for token in tokens]


def results_named(text: str, name: str) -> list[list[int]]:
    """The hex values of every result line called ``name``, in order."""
    return [hex_values(tokens) for line_name, tokens in parse_results(text) if line_name == name]
