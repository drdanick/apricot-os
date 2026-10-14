"""CAT and STAT, on a prepared disk.

STAT's expected output is computed independently from the disk image, so the
OS's block walking is checked against :mod:`test_tools.diskimage`.
"""

import pytest

from test_tools.diskimage import ROOT
from test_tools.expectations import expected_stat

pytestmark = pytest.mark.simulator

FILES = {"EMPTY": None, "HELLO": "hello", "F256": "f256", "F600": "f600", "BINARY": "binary", "BIG": "big"}


@pytest.fixture(scope="module")
def disk(make_disk, host_files):
    commands = []
    for name, source in FILES.items():
        commands.append(f"touch {name}")
        if source:
            commands.append(f"loadfile {name} {host_files[source]}")
    commands += ["touch EXE", f"loadfile EXE {host_files['hello']}", "toggleexec EXE",
                 "mkdir BIN", "cd BIN", "touch INNER", f"loadfile INNER {host_files['hello']}", "mkdir SUB", "cd .."]
    return make_disk(*commands)


@pytest.fixture(scope="module")
def session(boot, disk):
    return boot([
        *(f"CAT {name}" for name in ["EMPTY", "HELLO", "F256", "F600", "BINARY"]),
        "CAT BIN", "CAT NOPE", "CAT", "CAT TOOLONG",
        *(f"STAT {name}" for name in ["EMPTY", "HELLO", "F256", "F600", "EXE", "BIG", "BIN"]),
        "CD BIN", "STAT SUB", "STAT INNER",
        "STAT", "STAT NOPE", "STAT TOOLONG",
    ], disks={0: disk})


# --------------------------------------------------------------------- CAT

@pytest.mark.parametrize("name", ["HELLO", "F256", "F600"])
def test_cat_prints_the_file(session, host_files, name):
    expected = host_files[FILES[name]].read_bytes().decode().rstrip("\n")
    assert session[f"CAT {name}"] == expected


def test_cat_of_an_empty_file_prints_nothing(session):
    assert session["CAT EMPTY"] == ""


def test_cat_shows_non_printable_bytes_as_dots(session):
    # 41 03 42 7F 43 12 12 44 08 45 0D 46 80 FF 00 47 0A
    assert session["CAT BINARY"] == "A.B.C..D.E.F...G"


def test_cat_never_sends_terminal_commands(session):
    """A file containing 03, 12, 08 and 7F must not disturb the terminal."""
    assert session.anomalies == []


@pytest.mark.parametrize("command, error", [
    ("CAT BIN", "NOT A FILE"), ("CAT NOPE", "NOT FOUND"), ("CAT", "MISSING ARGUMENT"), ("CAT TOOLONG", "BAD NAME")])
def test_cat_errors(session, command, error):
    assert session[command] == f"ERROR: {error}"


# -------------------------------------------------------------------- STAT
@pytest.mark.parametrize("name", ["EMPTY", "HELLO", "F256", "F600", "EXE", "BIG", "BIN"])
def test_stat_in_the_root(session, disk, name):
    assert session[f"STAT {name}"] == expected_stat(disk, "/", ROOT, name)


@pytest.mark.parametrize("name", ["SUB", "INNER"])
def test_stat_in_a_subdirectory(session, disk, name):
    bin_entry = next(e for e in disk.entries(ROOT) if e.name == "BIN")
    assert session[f"STAT {name}"] == expected_stat(disk, "/BIN", bin_entry.location, name)


def test_stat_of_a_full_size_file_is_one_range(session, disk):
    assert session["STAT BIG"].splitlines()[5] == "BLOCKS:    127 (32512 BYTES, 12 UNUSED)"


@pytest.mark.parametrize("command, error", [
    ("STAT", "MISSING ARGUMENT"), ("STAT NOPE", "NOT FOUND"), ("STAT TOOLONG", "BAD NAME")])
def test_stat_errors(session, command, error):
    assert session[command] == f"ERROR: {error}"
