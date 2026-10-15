"""Test tooling for Apricot OS.

Modules:

* :mod:`~test_tools.config`: where the assembler, the simulator and fs-manager are.
* :mod:`~test_tools.assembler`: build the OS (with sanity checks) and assemble programs.
* :mod:`~test_tools.simulator`: boot the OS headlessly and type shell commands.
* :mod:`~test_tools.terminal`: replay terminal output into a screen and a transcript.
* :mod:`~test_tools.diskimage`: read, check and prepare disk images.
* :mod:`~test_tools.fsmanager`: create test disks with apricos-fs-manager.

The same tools are available from the command line: ``python -m test_tools --help``.
"""

from .assembler import AssemblyError, OsBuild, build_os
from .config import MissingTool, Tools
from .diskimage import DiskImage
from .fsmanager import FsManager, FsManagerError
from .simulator import Keys, Session, SessionResult, Type, Wait
from .terminal import Terminal

__all__ = [
    "AssemblyError", "DiskImage", "FsManager", "FsManagerError", "Keys", "MissingTool", "OsBuild", "Session",
    "SessionResult", "Terminal", "Tools", "Type", "Wait", "build_os",
]
