"""RM, MV and CP, the file size limit, and running out of disk space."""

import pytest

from test_tools.simulator import Wait

pytestmark = pytest.mark.simulator


# ---------------------------------------------------- RM, MV, CP, size limit

@pytest.fixture(scope="module")
def disk(make_disk, host_files):
    return make_disk(
        "touch BIG", f"loadfile BIG {host_files['big']}",         # 32500 bytes, 127 blocks
        "touch P", f"loadfile P {host_files['p250']}",
        "touch F600", f"loadfile F600 {host_files['f600']}",
        "mkdir DIR", "cd DIR", "touch INNER", "cd ..",
        "mkdir EMPTYD",
        "touch X", f"loadfile X {host_files['hello']}", "toggleexec X")


@pytest.fixture(scope="module")
def session(boot, disk):
    return boot([
        "WRITE BIG 0123456789ABCDE",      # 16 bytes: one over the limit
        "WRITE BIG 0123456789A",          # 12 bytes: exactly 32512
        "WRITE BIG X",
        "RM F600", "RM DIR", "RM EMPTYD", "RM NOPE", "RM", "RM TOOLONG",
        "MV P Q", "MV Q BIG", "MV NOPE Z", "MV Q", "MV Q TOOLONG",
        "MV DIR DOCS", "CD DOCS", "LS", "CD ..",
        "CP BIG BIG2", Wait(90),          # copying 127 blocks takes a while
        "CP X X2", "CP DOCS Z", "CP Q BIG", "CP Q", "CP NOPE Z",
        "LS", "CAT X2",
    ], disks={0: disk})


@pytest.fixture(scope="module")
def report(session):
    return session.disks[0].check()


def test_the_resulting_filesystem_is_valid_with_no_leaks(report):
    assert report.ok, report
    assert report.leaks == []


def test_write_refuses_to_pass_the_size_limit(session, host_files, report):
    assert session["WRITE BIG 0123456789ABCDE"] == "ERROR: FILE TOO BIG"
    assert session["WRITE BIG X"] == "ERROR: FILE TOO BIG"
    assert session["WRITE BIG 0123456789A"] == ""
    assert report.files["/BIG"].data == host_files["big"].read_bytes() + b"0123456789A\n"
    assert report.files["/BIG"].size == 32512


def test_rm_removes_a_file(report):
    assert "/F600" not in report.files


def test_rm_removes_an_empty_directory(report):
    assert "/EMPTYD/" not in report.directories


@pytest.mark.parametrize("command, error", [
    ("RM DIR", "DIRECTORY NOT EMPTY"), ("RM NOPE", "NOT FOUND"), ("RM", "MISSING ARGUMENT"),
    ("RM TOOLONG", "BAD NAME"),
    ("MV Q BIG", "ALREADY EXISTS"), ("MV NOPE Z", "NOT FOUND"), ("MV Q", "MISSING ARGUMENT"),
    ("MV Q TOOLONG", "BAD NAME"),
    ("CP DOCS Z", "NOT A FILE"), ("CP Q BIG", "ALREADY EXISTS"), ("CP Q", "MISSING ARGUMENT"),
    ("CP NOPE Z", "NOT FOUND"),
])
def test_errors(session, command, error):
    assert session[command] == f"ERROR: {error}"


def test_mv_renames_a_file(host_files, report):
    assert "/P" not in report.files
    assert report.files["/Q"].data == host_files["p250"].read_bytes()


def test_mv_renames_a_directory_with_its_contents(session, report):
    assert "/DOCS/" in report.directories and "/DIR/" not in report.directories
    assert session["LS"] == "INNER"


def test_cp_copies_a_full_size_file(report):
    original, copy = report.files["/BIG"], report.files["/BIG2"]
    assert copy.data == original.data
    assert not set(copy.blocks) & set(original.blocks)


def test_cp_keeps_the_executable_bit(session, report):
    assert report.files["/X2"].entry.executable
    assert report.files["/X2"].data == report.files["/X"].data
    assert "X2*" in session.all("LS")[-1].splitlines()
    assert session["CAT X2"] == "Hello, Apricot!"


def test_output_follows_the_terminal_protocol(session):
    assert session.anomalies == []


# ------------------------------------------------------------- disk full

@pytest.fixture(scope="module")
def full_disk(make_disk, host_files):
    disk = make_disk("touch P", f"loadfile P {host_files['p250']}", "touch F600", f"loadfile F600 {host_files['f600']}")
    filled = set(disk.free_sectors())
    disk.fill_free_space()
    return disk, filled


@pytest.fixture(scope="module")
def full_session(boot, full_disk):
    disk, _ = full_disk
    return boot(["WRITE P 0123456789ABCDEFGHI", "TOUCH NEW", "MKDIR D", "CP P P2", "CAT P"], disks={0: disk})


def test_a_full_disk_refuses_new_entries(full_session):
    for command in ["TOUCH NEW", "MKDIR D", "CP P P2"]:
        assert full_session[command] == "ERROR: DISK FULL", command


def test_write_keeps_what_fits_when_the_disk_fills(full_session, host_files):
    """P has 250 bytes in one block: 6 more fit before a new block is needed."""
    assert full_session["WRITE P 0123456789ABCDEFGHI"] == "ERROR: DISK FULL"
    report = full_session.disks[0].check()
    assert report.files["/P"].data == host_files["p250"].read_bytes() + b"012345"
    assert full_session["CAT P"].endswith("012345")


def test_a_full_disk_stays_consistent(full_session, full_disk):
    _, filled = full_disk
    report = full_session.disks[0].check()
    assert report.ok, report
    assert set(report.leaks) == filled       # only the sectors the test filled in


@pytest.fixture(scope="module")
def nearly_full_disk(make_disk, host_files):
    disk = make_disk("touch F600", f"loadfile F600 {host_files['f600']}")
    left = disk.fill_free_space(leave_free=2)
    return disk, left


@pytest.fixture(scope="module")
def nearly_full_session(boot, nearly_full_disk):
    disk, _ = nearly_full_disk
    return boot(["CP F600 F2", "TOUCH T", "WRITE T HI", "TOUCH U", "RM F600", "LS"], disks={0: disk})


def test_cp_undoes_its_allocations_when_the_disk_fills(nearly_full_session, nearly_full_disk):
    """F600 needs 4 sectors but only 2 are free; afterwards TOUCH and WRITE can use both."""
    _, left = nearly_full_disk
    assert nearly_full_session["CP F600 F2"] == "ERROR: DISK FULL"
    report = nearly_full_session.disks[0].check()
    assert "/F2" not in report.files
    assert [report.files["/T"].entry.location, *report.files["/T"].blocks] == left
    assert nearly_full_session["TOUCH U"] == "ERROR: DISK FULL"


def test_rm_frees_the_data_and_metadata_sectors(nearly_full_session, nearly_full_disk):
    disk, _ = nearly_full_disk
    f600 = disk.check().files["/F600"]
    freed = [f600.entry.location, *f600.blocks]
    after = nearly_full_session.disks[0]
    assert all(not after.is_allocated(*sector) for sector in freed)
    assert after.check().ok
    assert nearly_full_session["LS"] == "T"
