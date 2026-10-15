"""Where the external tools are.

The tests depend on nothing outside this repository except three tools:

* **apricosasm.jar**, the assembler, which goes in the root of the
  repository (next to ``assemble.sh``), and needs Java;
* **aprsim**, the simulator, built with TTY and port emulation;
* **apricosfsman**, the fs-manager binary, which prepares test disks.

The simulator and fs-manager are given as either a binary name, looked up on
the ``PATH`` (a system install), or a path to a binary (a fresh build):

==================  =================================  ===============================
Variable            Meaning                            Default
==================  =================================  ===============================
``APRSIM``          The simulator                      ``aprsim`` on the ``PATH``
``APRICOSFSMAN``    fs-manager                         ``apricosfsman`` on the ``PATH``
``APRICOSASM_JAR``  The assembler jar                  ``apricot-os/apricosasm.jar``
``JAVA``            The Java launcher                  ``java`` on the ``PATH``
==================  =================================  ===============================

With pytest, ``--aprsim NAME-OR-PATH`` and ``--fsman NAME-OR-PATH`` take
precedence over the variables.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from dataclasses import dataclass
from functools import cached_property
from pathlib import Path

OS_REPO = Path(__file__).resolve().parents[2]
OS_SOURCES = OS_REPO / "src"
ASSEMBLE_SCRIPT = OS_REPO / "assemble.sh"
ASSEMBLER_JAR = OS_REPO / "apricosasm.jar"
TESTS_DIR = OS_REPO / "tests"
PROGRAMS_DIR = TESTS_DIR / "programs"


class MissingTool(RuntimeError):
    """A tool the tests need could not be found."""


@dataclass(frozen=True)
class Tools:
    """Locations of the external tools.

    Each field is a name or path given explicitly; ``None`` means "use the
    environment variable, then the default".
    """

    aprsim: str | None = None
    fsman: str | None = None
    jar: str | None = None
    java_launcher: str | None = None

    @classmethod
    def from_environment(cls, aprsim: str | None = None, fsman: str | None = None) -> "Tools":
        return cls(aprsim=aprsim, fsman=fsman)

    @cached_property
    def java(self) -> str:
        java = self.java_launcher or os.environ.get("JAVA") or shutil.which("java")
        if not java:
            raise MissingTool("java was not found; install a JDK or set JAVA")
        return java

    @cached_property
    def assembler_jar(self) -> Path:
        jar = Path(self.jar or os.environ.get("APRICOSASM_JAR") or ASSEMBLER_JAR)
        if not jar.is_file():
            raise MissingTool(f"the assembler was not found at {jar}; put apricosasm.jar in the repository root "
                              "(see assemble.sh) or set APRICOSASM_JAR")
        return jar.resolve()

    @cached_property
    def simulator(self) -> str:
        """The simulator command: a name resolved on the PATH, or a path to a binary."""
        simulator = _find_binary(self.aprsim or os.environ.get("APRSIM") or "aprsim", "the simulator",
                                 "install aprsim or set APRSIM to its name or path (pytest: --aprsim)")
        usage = subprocess.run([simulator, "-h"], capture_output=True, text=True).stdout
        if "-f" not in usage:
            raise MissingTool(f"{simulator} was built without TTY/port emulation (no -f option)")
        return simulator

    @cached_property
    def fs_manager(self) -> str:
        """The fs-manager command: a name resolved on the PATH, or a path to a binary."""
        return _find_binary(self.fsman or os.environ.get("APRICOSFSMAN") or "apricosfsman", "fs-manager",
                            "install apricos-fs-manager or set APRICOSFSMAN to its name or path (pytest: --fsman)")


def _find_binary(wanted: str, what: str, advice: str) -> str:
    """Resolve a tool given as a binary name (looked up on the PATH) or a path."""
    found = str(Path(wanted).expanduser().resolve()) if os.sep in wanted else shutil.which(wanted)
    if not found or not Path(found).is_file() or not os.access(found, os.X_OK):
        raise MissingTool(f"{what} {wanted!r} was not found; {advice}")
    return found
