"""Reading, checking and preparing Apricot disk images.

A disk image is 32 tracks x 64 sectors x 256 bytes (512 KiB). Track 0 holds
the OS image (sectors 0-61), the volume information (sector 62) and the
space bitmap (sector 63). The filesystem format is described in
APRICOS_DEVELOPMENT_GUIDE.md, Appendix A and section 5.7.

:class:`DiskImage` gives structured access to an image, and
:meth:`DiskImage.check` validates the whole filesystem: every referenced
sector must be allocated and used once, names must be valid, block lists
must match file sizes, and allocated sectors nothing refers to are reported
as leaks.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

TRACKS = 32
SECTORS_PER_TRACK = 64
SECTOR_SIZE = 256
IMAGE_SIZE = TRACKS * SECTORS_PER_TRACK * SECTOR_SIZE
OS_SECTORS = 62
VOLUME_SECTOR = 62
BITMAP_SECTOR = 63
ROOT = (1, 0)
SIGNATURE = bytes([0xC0, 0x30, 0x0C, 0x03])
BOOT_FLAG = bytes([0xAA, 0x55])
MAX_FILE_SIZE = 127 * SECTOR_SIZE
ENTRIES_PER_DIRECTORY = 32

IN_USE, EXECUTABLE, IS_FILE = 0x80, 0x40, 0x20

Location = tuple[int, int]          # (track, sector)


@dataclass
class Entry:
    """A directory entry."""

    slot: int
    name: str
    is_file: bool
    executable: bool
    location: Location


@dataclass
class FileInfo:
    path: str
    entry: Entry
    size: int
    blocks: list[Location]
    data: bytes


@dataclass
class DirectoryInfo:
    path: str
    entry: Entry | None
    location: Location
    entries: list[Entry]


@dataclass
class CheckReport:
    """The result of :meth:`DiskImage.check`."""

    errors: list[str] = field(default_factory=list)
    leaks: list[Location] = field(default_factory=list)
    files: dict[str, FileInfo] = field(default_factory=dict)
    directories: dict[str, DirectoryInfo] = field(default_factory=dict)

    @property
    def ok(self) -> bool:
        return not self.errors

    def __str__(self) -> str:
        lines = [f"[{'d' if p in self.directories else 'f'}] {p}" for p in sorted({**self.files, **self.directories})]
        lines += [f"ERROR: {e}" for e in self.errors]
        if self.leaks:
            lines.append(f"{len(self.leaks)} leaked sectors: {self.leaks[:10]}")
        return "\n".join(lines)


class DiskImage:
    """A mutable 512 KiB Apricot disk image."""

    def __init__(self, data: bytes | bytearray | None = None) -> None:
        self.data = bytearray(data if data is not None else IMAGE_SIZE)
        if len(self.data) != IMAGE_SIZE:
            raise ValueError(f"disk images are {IMAGE_SIZE} bytes, not {len(self.data)}")

    # Construction and storage

    @classmethod
    def load(cls, path: Path) -> "DiskImage":
        return cls(path.read_bytes())

    def save(self, path: Path) -> Path:
        path.write_bytes(self.data)
        return path

    def copy(self) -> "DiskImage":
        return DiskImage(self.data)

    # Sectors

    @staticmethod
    def offset(track: int, sector: int) -> int:
        return (track * SECTORS_PER_TRACK + sector) * SECTOR_SIZE

    def sector(self, track: int, sector: int) -> bytes:
        start = self.offset(track, sector)
        return bytes(self.data[start:start + SECTOR_SIZE])

    def write_sector(self, track: int, sector: int, content: bytes) -> None:
        if len(content) != SECTOR_SIZE:
            raise ValueError("a sector is 256 bytes")
        start = self.offset(track, sector)
        self.data[start:start + SECTOR_SIZE] = content

    # Volume information

    @property
    def has_signature(self) -> bool:
        return self.sector(0, VOLUME_SECTOR)[:4] == SIGNATURE

    @property
    def volume_name(self) -> str:
        return self.sector(0, VOLUME_SECTOR)[4:12].split(b"\0")[0].decode("latin-1")

    @property
    def bootable(self) -> bool:
        return self.sector(0, VOLUME_SECTOR)[254:256] == BOOT_FLAG

    # Space bitmap

    def is_allocated(self, track: int, sector: int) -> bool:
        block = track * SECTORS_PER_TRACK + sector
        return bool(self.data[self.offset(0, BITMAP_SECTOR) + block // 8] >> (block % 8) & 1)

    def set_allocated(self, track: int, sector: int, allocated: bool = True) -> None:
        block = track * SECTORS_PER_TRACK + sector
        index = self.offset(0, BITMAP_SECTOR) + block // 8
        if allocated:
            self.data[index] |= 1 << (block % 8)
        else:
            self.data[index] &= ~(1 << (block % 8)) & 0xFF

    def free_sectors(self) -> list[Location]:
        """Free sectors of tracks 1-31, in allocation (first-fit) order."""
        return [(t, s) for t in range(1, TRACKS) for s in range(SECTORS_PER_TRACK) if not self.is_allocated(t, s)]

    def fill_free_space(self, leave_free: int = 0) -> list[Location]:
        """Mark every free sector allocated except the first ``leave_free``.

        Returns the sectors left free. Used to set up "disk full" tests; the
        sectors marked here show up as leaks in :meth:`check`.
        """
        free = self.free_sectors()
        for track, sector in free[leave_free:]:
            self.set_allocated(track, sector)
        return free[:leave_free]

    @property
    def allocated_count(self) -> int:
        """Allocated sectors in tracks 1-31."""
        return sum(self.is_allocated(t, s) for t in range(1, TRACKS) for s in range(SECTORS_PER_TRACK))

    # Filesystem structures

    def entries(self, location: Location) -> list[Entry]:
        """The in-use entries of the directory stored at ``location``."""
        raw = self.sector(*location)
        result = []
        for slot in range(ENTRIES_PER_DIRECTORY):
            entry = raw[slot * 8:slot * 8 + 8]
            if entry[0] & IN_USE:
                result.append(Entry(slot=slot,
                                    name=entry[2:8].split(b"\0")[0].decode("latin-1"),
                                    is_file=bool(entry[0] & IS_FILE),
                                    executable=bool(entry[0] & EXECUTABLE),
                                    location=(entry[0] & 0x1F, entry[1] & 0x3F)))
        return result

    def file_blocks(self, metadata: Location) -> tuple[int, list[Location]]:
        """A file's size and its data block locations, from its metadata sector."""
        raw = self.sector(*metadata)
        blocks = [(raw[2 + 2 * k], raw[3 + 2 * k] & 0x3F) for k in range(127) if raw[2 + 2 * k]]
        return raw[0] | raw[1] << 8, blocks

    def read_file(self, metadata: Location) -> bytes:
        size, blocks = self.file_blocks(metadata)
        return b"".join(self.sector(*b) for b in blocks)[:size]

    def check(self) -> CheckReport:
        """Validate the filesystem and describe every file and directory."""
        report = CheckReport()
        references: dict[Location, str] = {}

        def claim(location: Location, owner: str) -> bool:
            track, sector = location
            if not (1 <= track < TRACKS and 0 <= sector < SECTORS_PER_TRACK):
                report.errors.append(f"{owner}: invalid sector {track}/{sector}")
                return False
            if location in references:
                report.errors.append(f"{owner}: sector {track}/{sector} is also used by {references[location]}")
                return False
            references[location] = owner
            if not self.is_allocated(track, sector):
                report.errors.append(f"{owner}: sector {track}/{sector} is free in the bitmap")
            return True

        if not self.has_signature:
            report.errors.append("no disk signature")
        if any(self.is_allocated(0, s) is False for s in range(SECTORS_PER_TRACK)):
            report.errors.append("track 0 is not fully allocated")
        if not self.is_allocated(*ROOT):
            report.errors.append("the root directory (1/0) is not allocated")
            return report
        references[ROOT] = "/"
        self._check_directory(ROOT, "/", None, report, claim, depth=0)

        report.leaks = [(t, s) for t in range(1, TRACKS) for s in range(SECTORS_PER_TRACK)
                        if self.is_allocated(t, s) and (t, s) not in references]
        return report

    def _check_directory(self, location, path, entry, report, claim, depth) -> None:
        if depth > 16:
            report.errors.append(f"{path}: nested too deeply (a cycle?)")
            return
        entries = self.entries(location)
        report.directories[path] = DirectoryInfo(path, entry, location, entries)
        raw = self.sector(*location)
        names = set()
        for item in entries:
            name_bytes = raw[item.slot * 8 + 2:item.slot * 8 + 8]
            child = path + item.name
            if (not item.name or item.name.startswith(".") or
                    any(c <= 0x20 or c >= 0x7F or c == ord("/") for c in item.name.encode("latin-1"))):
                report.errors.append(f"{path}: entry {item.slot} has an invalid name {name_bytes!r}")
            if b"\0" in name_bytes and any(name_bytes[name_bytes.index(b"\0"):]):
                report.errors.append(f"{child}: name is not NUL padded")
            if item.name in names:
                report.errors.append(f"{path}: duplicate name {item.name}")
            names.add(item.name)
            if not claim(item.location, child if item.is_file else child + "/"):
                continue
            if not item.is_file:
                self._check_directory(item.location, child + "/", item, report, claim, depth + 1)
                continue
            size, blocks = self.file_blocks(item.location)
            raw_meta = self.sector(*item.location)
            used_slots = [k for k in range(127) if raw_meta[2 + 2 * k]]
            if size > MAX_FILE_SIZE:
                report.errors.append(f"{child}: size {size} is over the {MAX_FILE_SIZE}-byte limit")
            if used_slots != list(range(len(used_slots))):
                report.errors.append(f"{child}: block slots are not contiguous: {used_slots}")
            if len(blocks) != -(-size // SECTOR_SIZE):
                report.errors.append(f"{child}: {len(blocks)} blocks for {size} bytes")
            for index, block in enumerate(blocks):
                claim(block, f"{child} block {index}")
            report.files[child] = FileInfo(child, item, size, blocks, self.read_file(item.location))
