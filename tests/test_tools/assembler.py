"""Building Apricot OS and assembling programs with apricosasm.

:func:`build_os` assembles a copy of ``apricot-os/src`` the way
``assemble.sh`` does (the unit list is read from that script) and checks the
result for mistakes the assembler itself doesn't report:

* **segment overflow**: a unit is larger than the gap before the next unit's
  ``#segment`` (or than segment 61, the last one loaded at boot);
* **page-end branches**: an immediate branch whose opcode sits at offset
  0xFE or 0xFF of a page lands in the next page;
* **cross-page local calls**: ``OS_LOCALSYSCALL``/``OS_CALLFUNC_LOCAL`` only
  set the low byte of the target, so the callee must share the caller's page.

The returned :class:`OsBuild` can also assemble extra programs against the
OS sources, for loading at an address of their own.
"""

from __future__ import annotations

import re
import shutil
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

from .config import ASSEMBLE_SCRIPT, OS_SOURCES, Tools

SEGMENT_SIZE = 256
FIRST_UNLOADED_SEGMENT = 62     # stage 2 loads segments 1-61 from disk 0


class AssemblyError(RuntimeError):
    """apricosasm reported an error."""


@dataclass(frozen=True)
class Unit:
    """One assembled unit of the OS image."""

    file: str
    segment: int
    size: int
    budget: int

    @property
    def segments(self) -> range:
        return range(self.segment, self.segment + max(1, -(-self.size // SEGMENT_SIZE)))

    @property
    def overflows(self) -> bool:
        return self.size > self.budget


@dataclass
class OsBuild:
    """The result of :func:`build_os`."""

    directory: Path
    tools: Tools
    boot_image: bytes
    disk_image: bytes
    units: list[Unit]
    symbols: dict[str, list[int]]
    page_end_branches: list[str] = field(default_factory=list)
    cross_page_local_calls: list[str] = field(default_factory=list)

    @property
    def problems(self) -> list[str]:
        """Everything that makes the build unsafe to run, as readable messages."""
        problems = [f"{u.file} is {u.size} bytes but only has room for {u.budget}"
                    for u in self.units if u.overflows]
        problems += [f"page-end branch: {b}" for b in self.page_end_branches]
        problems += [f"cross-page local call: {c}" for c in self.cross_page_local_calls]
        return problems

    def unit(self, file: str) -> Unit:
        return next(u for u in self.units if u.file == file)

    def address(self, label: str) -> int:
        """The address of a label. The symbol file is unqualified, so it must be unique."""
        addresses = self.symbols.get(label.lower(), [])
        if len(addresses) != 1:
            raise KeyError(f"label {label!r} has {len(addresses)} addresses in symbols.sym")
        return addresses[0]

    def assemble_program(self, source: Path, *support: Path) -> bytes:
        """Assemble a standalone program (in PB format) against this build's sources.

        The program, and any ``support`` files it includes, are copied into
        the build directory, so it can ``#include`` any OS unit. The program
        gets the same page checks as the OS build; a problem raises
        :class:`AssemblyError`.
        """
        for path in (*support, source):
            shutil.copy(path, self.directory / path.name)
        target = self.directory / source.name
        output = _run_assembler(self.tools, [target.name], self.directory)
        _raise_on_errors(output)
        binary = target.with_suffix(".bin").read_bytes()
        program_symbols = _program_symbols(self.tools, target, self.directory)
        problems = find_page_end_branches(binary, program_symbols)
        problems += find_cross_page_local_calls(target, program_symbols)
        if problems:
            raise AssemblyError(f"{source.name}: " + "; ".join(problems))
        return binary


def build_os(tools: Tools, destination: Path, overrides: dict[str, Path] | None = None) -> OsBuild:
    """Assemble the OS into ``destination`` and check it.

    ``overrides`` replaces source files in the copy, for example
    ``{"testprogram.asm": Path("my_test.asm")}``.
    """
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(OS_SOURCES, destination)
    for name, replacement in (overrides or {}).items():
        shutil.copy(replacement, destination / name)

    _raise_on_errors(_run_assembler(tools, ["-sh", "boot.asm"], destination))
    boot_image = (destination / "boot.bin").read_bytes()

    units = units_from_assemble_script(ASSEMBLE_SCRIPT)
    output = _run_assembler(tools, ["-ldsh", *units], destination)
    _raise_on_errors(output)
    sizes = {f"{name}.asm": int(words) for words, name in re.findall(r"Writing (\d+) words to (\S+)\.bin", output)}
    missing = [u for u in units if u not in sizes]
    if missing:
        raise AssemblyError(f"no output for {missing}:\n{output}")

    symbols = read_symbols(destination / "symbols.sym")
    build = OsBuild(
        directory=destination,
        tools=tools,
        boot_image=boot_image,
        disk_image=(destination / "link.bin").read_bytes(),
        units=_unit_budgets(destination, units, sizes),
        symbols=symbols,
    )
    for unit in build.units:
        build.page_end_branches += [f"{unit.file}: {hit}" for hit in
                                    find_page_end_branches((destination / unit.file).with_suffix(".bin").read_bytes(), symbols)]
        build.cross_page_local_calls += find_cross_page_local_calls(destination / unit.file, symbols)
    return build


def _program_symbols(tools: Tools, source: Path, directory: Path) -> dict[str, list[int]]:
    """The symbols of a single program, without overwriting the OS build's symbols.sym."""
    scratch = directory / ".program-symbols"
    scratch.mkdir(exist_ok=True)
    for path in directory.glob("*.asm"):
        shutil.copy(path, scratch / path.name)
    _run_assembler(tools, ["-s", source.name], scratch)
    return read_symbols(scratch / "symbols.sym")


def units_from_assemble_script(script: Path) -> list[str]:
    """The ``-ldsh`` unit list in assemble.sh, in order."""
    text = script.read_text()
    block = text.split("-ldsh", 1)[1].split("&&", 1)[0]
    return re.findall(r"([\w]+\.asm)", block)


def read_symbols(path: Path) -> dict[str, list[int]]:
    """Parse symbols.sym (``decimalAddress:label`` lines) into label -> addresses."""
    symbols: dict[str, list[int]] = {}
    for line in path.read_text().splitlines():
        address, _, label = line.strip().partition(":")
        if address.isdigit():
            symbols.setdefault(label, []).append(int(address))
    return symbols


def read_pb(data: bytes) -> tuple[int, bytes]:
    """Split a PB-format program into its origin and its bytes."""
    if data[:2] != b"PB":
        raise ValueError("not a PB file")
    size = data[2] | data[3] << 8
    origin = data[4] | data[5] << 8
    return origin, data[6:6 + size]


def find_page_end_branches(pb_file: bytes, symbols: dict[str, list[int]]) -> list[str]:
    """Immediate branches whose opcode is at page offset 0xFE/0xFF.

    The unit is decoded linearly, so data inside it can produce false hits;
    each hit names the nearest preceding label to make checking easy.
    """
    origin, code = read_pb(pb_file)
    by_address = sorted((address, name) for name, addresses in symbols.items() for address in addresses)
    hits = []
    offset = 0
    while offset < len(code):
        opcode = code[offset]
        high = opcode >> 4
        two_bytes = high in (0x7, 0x9, 0xB) or (high == 0xC and opcode != 0xCE)
        address = origin + offset
        if high == 0xC and opcode & 0x01 and opcode & 0x0E and address & 0xFF >= 0xFE:
            label = max(((a, n) for a, n in by_address if a <= address), default=(0, "?"))[1]
            hits.append(f"{address:#06x} (after label {label})")
        offset += 2 if two_bytes else 1
    return hits


def find_cross_page_local_calls(source: Path, symbols: dict[str, list[int]]) -> list[str]:
    """``OS_LOCALSYSCALL``/``OS_CALLFUNC_LOCAL`` calls whose callee is in another page."""
    problems = []
    last_label = None
    for number, line in enumerate(source.read_text().splitlines(), start=1):
        code = line.split(";", 1)[0]
        if match := re.match(r"\s*([A-Za-z_]\w*):", code):
            last_label = match.group(1).lower()
        match = re.search(r"(LOCALSYSCALL|CALLFUNC_LOCAL)\s+(\w+)", code, re.IGNORECASE)
        if match and "#macro" not in code:
            callee_pages = {a >> 8 for a in symbols.get(match.group(2).lower(), [])}
            if last_label is None:              # code before the first label is on the first page
                caller_pages = {_segment_of(source)}
            else:
                caller_pages = {a >> 8 for a in symbols.get(last_label, [])}
            if not callee_pages & caller_pages:
                where = f"after label {last_label}" if last_label else "before the first label"
                problems.append(f"{source.name}:{number}: {match.group(0)} ({where}) calls into another page")
    return problems


def _unit_budgets(directory: Path, units: list[str], sizes: dict[str, int]) -> list[Unit]:
    segments = sorted((_segment_of(directory / unit), unit) for unit in units)
    result = []
    for index, (segment, unit) in enumerate(segments):
        following = segments[index + 1][0] if index + 1 < len(segments) else FIRST_UNLOADED_SEGMENT
        result.append(Unit(unit, segment, sizes[unit], (following - segment) * SEGMENT_SIZE))
    return result


def _segment_of(source: Path) -> int:
    for line in source.read_text().splitlines():
        if match := re.match(r"\s*#segment\s+(\S+)", line, re.IGNORECASE):
            return int(match.group(1), 0)
    return 0


def _run_assembler(tools: Tools, arguments: list[str], cwd: Path) -> str:
    result = subprocess.run([tools.java, "-jar", str(tools.assembler_jar), *arguments],
                            cwd=cwd, capture_output=True, text=True)
    output = result.stdout + result.stderr
    if result.returncode != 0:
        raise AssemblyError(output)
    return output


def _raise_on_errors(output: str) -> None:
    if re.search(r"^Error assembling|FAIL", output, re.MULTILINE):
        raise AssemblyError(output)
