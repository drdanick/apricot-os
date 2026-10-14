"""What OS commands should print, computed independently from a disk image."""

from __future__ import annotations

from .diskimage import DiskImage


def expected_stat(disk: DiskImage, parent_path: str, parent: tuple[int, int], name: str) -> str:
    """What STAT should print for ``name`` in the directory at ``parent``."""
    entry = next(e for e in disk.entries(parent) if e.name == name)
    path = ("" if parent_path == "/" else parent_path) + "/" + name
    lines = [f"NAME:      {name}", f"PATH:      {path}",
             f"TYPE:      {'FILE' if entry.is_file else 'DIRECTORY'}",
             f"EXEC:      {'YES' if entry.executable else 'NO'}"]
    track, sector = entry.location
    if entry.is_file:
        size, blocks = disk.file_blocks(entry.location)
        ranges = block_ranges(blocks)
        lines += [f"SIZE:      {size} BYTE{'' if size == 1 else 'S'}",
                  f"BLOCKS:    {len(blocks)} ({len(blocks) * 256} BYTES, {len(blocks) * 256 - size} UNUSED)",
                  f"FRAGMENTS: {len(ranges)}",
                  f"ON DISK:   {len(blocks) + 1} SECTOR{'' if len(blocks) + 1 == 1 else 'S'}",
                  f"METADATA:  {track}/{sector}",
                  f"DATA:      {' '.join(ranges) if ranges else '(NONE)'}"]
    else:
        children = disk.entries(entry.location)
        files = sum(c.is_file for c in children)
        directories = len(children) - files
        lines += [f"ENTRIES:   {len(children)} OF 32 ({files} FILE{'' if files == 1 else 'S'}, "
                  f"{directories} DIRECTOR{'Y' if directories == 1 else 'IES'})",
                  f"SECTOR:    {track}/{sector}"]
    lines.append(f"ENTRY:     {entry.slot + 1} OF 32 IN {parent_path.rstrip('/') or '/'} ({parent[0]}/{parent[1]})")
    return "\n".join(lines)


def block_ranges(blocks: list[tuple[int, int]]) -> list[str]:
    """Blocks as STAT prints them: runs of consecutive sectors become "first-last"."""
    ranges, start, previous = [], None, None
    for block in blocks:
        number = block[0] * 64 + block[1]
        if previous is not None and number == previous[0] * 64 + previous[1] + 1:
            previous = block
            continue
        if start is not None:
            ranges.append(_range(start, previous))
        start = previous = block
    if start is not None:
        ranges.append(_range(start, previous))
    return ranges


def _range(first, last):
    text = f"{first[0]}/{first[1]}"
    return text if first == last else f"{text}-{last[0]}/{last[1]}"
