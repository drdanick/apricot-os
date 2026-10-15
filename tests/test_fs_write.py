"""TOUCH, MKDIR and WRITE, starting from an empty filesystem.

The bitmap is pre-filled up to 1/56 so that the allocations land where the
tests want them:

* five TOUCH/MKDIR entries take 1/57-1/61;
* file C (metadata 1/62) gets blocks 1/63 and 2/0, one range across a track;
* files A and B are written alternately, so their blocks interleave and each
  has two fragments.
"""

import pytest

from test_tools.diskimage import ROOT
from test_tools.expectations import expected_stat

pytestmark = pytest.mark.simulator

PREFILLED = [(1, s) for s in range(1, 57)]
LONG_TEXT = ("0123456789" * 12)[:120]       # 3 WRITEs = 363 bytes = 2 blocks
SHORT_TEXT = ("ABCDEFGHIJ" * 9)[:90]        # 3 WRITEs = 273 bytes = 2 blocks


@pytest.fixture(scope="module")
def initial_disk(make_disk):
    disk = make_disk()
    for track, sector in PREFILLED:
        disk.set_allocated(track, sector)
    return disk


@pytest.fixture(scope="module")
def session(boot, initial_disk):
    return boot([
        "TOUCH EMPTYF", "MKDIR DIR", "TOUCH ABCDEF",
        "TOUCH EMPTYF", "MKDIR EMPTYF", "TOUCH TOOLONG", "TOUCH", "MKDIR .X", "MKDIR A/B",
        "LS",
        "CD DIR", "TOUCH IN", "MKDIR SUB", "LS", "CD ..",
        *[f"WRITE C {LONG_TEXT}"] * 3,
        *[f"WRITE {name} {SHORT_TEXT}" for _ in range(3) for name in ("A", "B")],
        "WRITE NOTE", "WRITE DIR X", "WRITE A/B X", "WRITE TOOLONG X",
        "WRITE HELLO HELLO WORLD", "WRITE HELLO", "WRITE HELLO  TWO SPACES",
        "CAT HELLO", "CAT C",
        "STAT C", "STAT A", "STAT B", "STAT DIR", "STAT EMPTYF",
    ], disks={0: initial_disk}, command_wait=1.0)


@pytest.fixture(scope="module")
def disk(session):
    return session.disks[0]


@pytest.fixture(scope="module")
def report(disk):
    return disk.check()


def test_the_resulting_filesystem_is_valid(report):
    assert report.ok, report
    assert report.leaks == PREFILLED          # only the sectors the test filled in


def test_touch_and_mkdir_create_entries(session, report):
    assert session["LS"].splitlines()[:3] == ["EMPTYF", "DIR/", "ABCDEF"]
    assert report.files["/EMPTYF"].size == 0
    assert "/DIR/" in report.directories


def test_entries_are_created_in_a_subdirectory(session, report):
    assert session.all("LS")[1].splitlines() == ["IN", "SUB/"]
    assert "/DIR/IN" in report.files and "/DIR/SUB/" in report.directories


def test_allocation_is_first_fit(disk):
    assert [e.location for e in disk.entries(ROOT)][:3] == [(1, 57), (1, 58), (1, 59)]


@pytest.mark.parametrize("command, error", [
    ("TOUCH EMPTYF", "ALREADY EXISTS"),
    ("MKDIR EMPTYF", "ALREADY EXISTS"),
    ("TOUCH TOOLONG", "BAD NAME"),
    ("TOUCH", "MISSING ARGUMENT"),
    ("MKDIR .X", "BAD NAME"),
    ("MKDIR A/B", "BAD NAME"),
    ("WRITE NOTE", "MISSING ARGUMENT"),
    ("WRITE DIR X", "NOT A FILE"),
    ("WRITE A/B X", "BAD NAME"),
    ("WRITE TOOLONG X", "BAD NAME"),
])
def test_errors(session, command, error):
    assert session.all(command)[-1] == f"ERROR: {error}"     # the last time the command was typed


def test_write_appends_lines(session, report):
    assert report.files["/C"].data == (LONG_TEXT + "\n").encode() * 3
    assert session["CAT C"] == "\n".join([LONG_TEXT] * 3)


def test_write_keeps_the_text_after_the_first_space(report):
    assert report.files["/HELLO"].data == b"HELLO WORLD\n TWO SPACES\n"


def test_write_with_no_text_creates_nothing_extra(session):
    assert session["WRITE HELLO"] == "ERROR: MISSING ARGUMENT"


def test_a_file_can_span_a_track_boundary(report):
    assert report.files["/C"].blocks == [(1, 63), (2, 0)]


def test_interleaved_writes_fragment_files(report):
    assert report.files["/A"].blocks == [(2, 2), (2, 5)]
    assert report.files["/B"].blocks == [(2, 4), (2, 6)]
    assert report.files["/A"].data == (SHORT_TEXT + "\n").encode() * 3


@pytest.mark.parametrize("name", ["C", "A", "B", "DIR", "EMPTYF"])
def test_stat_matches_the_disk(session, disk, name):
    assert session[f"STAT {name}"] == expected_stat(disk, "/", ROOT, name)


def test_stat_shows_the_track_crossing_range_and_fragments(session):
    assert "DATA:      1/63-2/0" in session["STAT C"]
    assert "FRAGMENTS: 2" in session["STAT A"] and "DATA:      2/2 2/5" in session["STAT A"]


def test_fs_manager_reads_the_result(fs_manager, disk, tmp_path):
    image = disk.save(tmp_path / "result.dsk")
    listing = fs_manager.run(image, ["ls", "cd DIR", "ls"])
    for name in ["EMPTYF", "DIR/", "ABCDEF", "C", "A", "B", "HELLO", "IN", "SUB/"]:
        assert name in listing


def test_output_follows_the_terminal_protocol(session):
    assert session.anomalies == []
