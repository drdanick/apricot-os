"""Creating test disks with apricos-fs-manager.

fs-manager is the host-side tool for Apricot disk images. It reads commands
on standard input (``mount``, ``format``, ``mkdir``, ``cd``, ``touch``,
``loadfile``, ``toggleexec``, ``unmount``, ...). The tests use it to prepare
disks independently of the OS's own filesystem code, so the two
implementations check each other.

Known fs-manager bugs (see the development guide, Appendix A): ``loadfile``
into a non-empty file corrupts data, and ``savefile`` can truncate files.
Prepare files with a single ``loadfile`` into a fresh ``touch``.
"""

from __future__ import annotations

import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

from .config import Tools
from .diskimage import DiskImage


class FsManagerError(RuntimeError):
    """An fs-manager command sequence failed."""


@dataclass(frozen=True)
class FsManager:
    binary: str

    @classmethod
    def from_tools(cls, tools: Tools) -> "FsManager":
        return cls(tools.fs_manager)

    def run(self, image: Path, commands: list[str], create: bool = False) -> str:
        """Mount ``image``, run ``commands``, then unmount (which saves) and exit.

        With ``create``, a new blank image is made first (``newdisk``).
        """
        lines = ([f"newdisk {image}"] if create else []) + [f"mount {image}", *commands, "unmount", "exit"]
        script = "\n".join(lines) + "\n"
        # fs-manager prints 6-character names without their (missing) NUL
        # terminator, so its output isn't always valid UTF-8.
        result = subprocess.run([self.binary], input=script, capture_output=True, encoding="latin-1")
        if "unmounted" not in result.stdout:
            raise FsManagerError(f"fs-manager did not unmount {image}:\n{result.stdout}{result.stderr}")
        return result.stdout

    def create_disk(self, base: bytes | None, commands: list[str], volume: str = "APRICOT") -> DiskImage:
        """Format a disk and run ``commands`` on it.

        ``base`` is the image to start from, normally the OS image: ``format``
        only rewrites the volume information, the bitmap and the root
        directory, so an OS image stays bootable. With ``base=None`` a blank
        data disk is created instead.
        """
        with tempfile.TemporaryDirectory() as scratch:
            image = Path(scratch) / "disk.dsk"
            if base is not None:
                image.write_bytes(base)
            self.run(image, [f"format {volume}", *commands], create=base is None)
            return DiskImage.load(image)
