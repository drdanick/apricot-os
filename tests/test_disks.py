"""DISKSEL, DISKSTAT and FSSTAT, with several disks attached.

Disk 0 boots the OS and has some files; disk 1 is blank (all zeros); disk 2
is a data volume made by fs-manager; there is no disk 3.
"""

import pytest

from test_tools.diskimage import DiskImage
from test_tools.simulator import Keys

pytestmark = pytest.mark.simulator


@pytest.fixture(scope="module")
def disks(make_disk, host_files):
    return {
        0: make_disk("mkdir BIN", "touch README", f"loadfile README {host_files['hello']}"),
        1: DiskImage(),
        2: make_disk("touch HELLO", f"loadfile HELLO {host_files['hello']}", "mkdir STUFF",
                     volume="DATA2", blank=True),
    }


@pytest.fixture(scope="module")
def session(boot, disks):
    return boot([
        "DISKSTAT", "FSSTAT",
        "CD BIN",
        "DISKSEL 3", "DISKSEL 9", "DISKSEL X", "DISKSEL", "DISKSEL 12",
        "DISKSTAT", "PWD",
        "DISKSEL 2", "PWD", "LS", "DISKSTAT", "FSSTAT", "CAT HELLO",
        "DISKSEL 1", "DISKSTAT", "FSSTAT", "LS",
        "FORMAT DATA", Keys("y"),
        "TOUCH A", "WRITE A HI THERE", "FSSTAT",
        "DISKSEL 0", "LS",
        "DISKSEL 1", "CAT A",
    ], disks=disks)


def fsstat_text(used: int) -> str:
    free = 1984 - used
    return "\n".join([
        "FILESYSTEM: OK",
        f"USED:       {used} SECTORS ({used // 4} KB)",          # FSSTAT always says SECTORS
        f"FREE:       {free} SECTORS ({free // 4} KB)",
        "TOTAL:      1984 SECTORS (496 KB)"])


def test_diskstat_of_the_boot_disk(session):
    assert session.output(0).text == "DISK:      0\nSIGNATURE: VALID\nVOLUME:    APRICOT\nBOOTABLE:  YES"


def test_fsstat_counts_the_allocated_sectors(session, disks):
    assert session.output(1).text == fsstat_text(disks[0].allocated_count)


@pytest.mark.parametrize("index, command", [(3, "DISKSEL 3"), (4, "DISKSEL 9"), (5, "DISKSEL X"), (7, "DISKSEL 12")])
def test_disksel_of_a_missing_or_invalid_disk(session, index, command):
    assert session.output(index).command == command
    assert session[index] == "ERROR: NO SUCH DISK"


def test_disksel_without_an_argument(session):
    assert session[6] == "ERROR: MISSING ARGUMENT"


def test_a_failed_disksel_changes_nothing(session):
    assert session[8].startswith("DISK:      0")
    assert session[9] == "/BIN"


def test_disksel_switches_disk_and_returns_to_the_root(session):
    assert session[10] == ""
    assert session[11] == "/"
    assert session[12].splitlines() == ["HELLO", "STUFF/"]
    assert session[15] == "Hello, Apricot!"


def test_diskstat_of_a_data_volume(session):
    # fs-manager's format always sets the boot flag
    assert session[13] == "DISK:      2\nSIGNATURE: VALID\nVOLUME:    DATA2\nBOOTABLE:  YES"


def test_fsstat_of_a_data_volume(session, disks):
    assert session[14] == fsstat_text(disks[2].allocated_count)


def test_disksel_of_a_blank_disk(session):
    assert session[16] == "NO FILESYSTEM - TYPE FORMAT"
    assert session[17] == "DISK:      1\nSIGNATURE: INVALID"
    assert session[18] == "FILESYSTEM: NO SIGNATURE"
    assert session[19] == "ERROR: NO FILESYSTEM"


def test_format_sets_up_a_blank_disk(session):
    assert session[20] == "FORMAT DISK 1? (Y/N) y"
    disk = session.disks[1]
    assert disk.has_signature and disk.volume_name == "DATA" and not disk.bootable
    report = disk.check()
    assert report.ok, report
    assert report.files["/A"].data == b"HI THERE\n"


def test_fsstat_after_writing_to_the_new_disk(session):
    assert session[23] == fsstat_text(3)          # root, A's metadata, A's data block


def test_each_disk_keeps_its_own_files(session):
    assert session[25].splitlines() == ["BIN/", "README"]
    assert session[27] == "HI THERE"


def test_other_disks_are_untouched(session, disks):
    assert session.disks[2].data == disks[2].data
    filesystem = 62 * 256
    assert session.disks[0].data[filesystem:] == disks[0].data[filesystem:]


def test_output_follows_the_terminal_protocol(session):
    assert session.anomalies == []
