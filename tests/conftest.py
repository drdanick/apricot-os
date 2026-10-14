"""Shared pytest fixtures for the Apricot OS tests.

Tests that boot the OS are marked ``simulator`` (they take seconds each);
run only the fast ones with ``pytest -m "not simulator"``.

Booting is the slow part, so most test modules run one session with many
commands in a module-scoped fixture, and each test checks one command's
output.
"""

from __future__ import annotations

import random
from pathlib import Path
from typing import Callable

import pytest

from test_tools import DiskImage, FsManager, MissingTool, OsBuild, Session, SessionResult, Tools, build_os
from test_tools.programs import Program, assemble_programs

LIBRARY_PROGRAMS = ["test_memutil", "test_math", "test_disp", "test_osutil", "test_diskio",
                    "test_diskalloc", "fault_bad_sector", "fault_track_zero"]


def pytest_addoption(parser):
    parser.addoption("--aprsim", metavar="NAME-OR-PATH", default=None,
                     help="the simulator: a binary name on the PATH or a path to a binary (default: $APRSIM, then aprsim)")
    parser.addoption("--fsman", metavar="NAME-OR-PATH", default=None,
                     help="fs-manager: a binary name on the PATH or a path to a binary (default: $APRICOSFSMAN, then apricosfsman)")


def pytest_configure(config):
    config.addinivalue_line("markers", "simulator: boots Apricot OS in aprsim (slow)")


def _require(get: Callable):
    try:
        return get()
    except MissingTool as missing:
        pytest.skip(str(missing))


@pytest.fixture(scope="session")
def tools(request) -> Tools:
    tools = Tools.from_environment(aprsim=request.config.getoption("--aprsim"),
                                   fsman=request.config.getoption("--fsman"))
    _require(lambda: (tools.java, tools.assembler_jar))
    return tools


@pytest.fixture(scope="session")
def os_build(tools, tmp_path_factory) -> OsBuild:
    """The OS, assembled from the current sources."""
    return build_os(tools, tmp_path_factory.mktemp("build") / "os")


@pytest.fixture(scope="session")
def fs_manager(tools) -> FsManager:
    _require(lambda: tools.fs_manager)
    return FsManager.from_tools(tools)


@pytest.fixture(scope="session")
def host_files(tmp_path_factory) -> dict[str, Path]:
    """Files to copy onto test disks with fs-manager's ``loadfile``."""
    directory = tmp_path_factory.mktemp("host-files")
    generator = random.Random(1)
    lines = b"".join(b"LINE %03d abcdefghijklmnopqrstuvwxyz0123456789.....\n" % i for i in range(12))
    contents = {
        "hello": b"Hello, Apricot!\n",
        "f256": b"0123456789ABCDE\n" * 16,
        "f600": lines[:600],
        "binary": bytes([0x41, 0x03, 0x42, 0x7F, 0x43, 0x12, 0x12, 0x44, 0x08, 0x45,
                         0x0D, 0x46, 0x80, 0xFF, 0x00, 0x47, 0x0A]),
        "p250": b"P" * 249 + b"\n",
        "big": bytes(generator.randrange(256) for _ in range(32500)),
    }
    paths = {}
    for name, data in contents.items():
        paths[name] = directory / f"{name}.dat"
        paths[name].write_bytes(data)
    return paths


@pytest.fixture(scope="session")
def make_disk(os_build, fs_manager) -> Callable[..., DiskImage]:
    """``make_disk(fs-manager commands..., volume="APRICOT", blank=False)``: a formatted test disk.

    By default the disk carries the OS image, so it can be booted.
    """
    def make(*commands: str, volume: str = "APRICOT", blank: bool = False) -> DiskImage:
        return fs_manager.create_disk(None if blank else os_build.disk_image, list(commands), volume=volume)
    return make


@pytest.fixture(scope="session")
def library_programs(os_build) -> dict[str, Program]:
    """The test programs in tests/programs, assembled against the current OS."""
    return assemble_programs(os_build, LIBRARY_PROGRAMS)


@pytest.fixture(scope="session")
def boot(tools, os_build) -> Callable[..., SessionResult]:
    """``boot(steps, disks={0: image}, programs=[...], ...)``: run one simulator session.

    The session must end normally (F1); a simulator crash fails the test.
    """
    _require(lambda: tools.simulator)

    def run(steps, disks: dict[int, DiskImage] | None = None, programs: list[Program] = (), **options) -> SessionResult:
        session = Session(tools, os_build, disks=disks or {}, programs=[p.binary for p in programs], **options)
        result = session.run(steps)
        assert result.simulator_status == "exited with code 0", result.simulator_status
        return result
    return run
