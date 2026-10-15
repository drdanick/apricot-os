"""Running without a filesystem, and FORMAT."""

import pytest

from test_tools.simulator import ENTER, Keys

pytestmark = pytest.mark.simulator

FS_COMMANDS = ["LS", "CD X", "PWD", "CAT X", "STAT X", "TOUCH X", "MKDIR X", "WRITE X Y", "RM X", "MV X Y", "CP X Y"]


@pytest.fixture(scope="module")
def session(boot):
    """Boots the plain build image, which has a disk signature but no filesystem."""
    return boot([
        *FS_COMMANDS,
        "FSSTAT", "DISKSTAT",
        "FORMAT TOOLONGNM",
        "FORMAT", Keys(ENTER.decode()),
        "FORMAT", Keys("N"),
        "LS",
        "FORMAT", Keys("Y"),
        "LS", "FSSTAT", "DISKSTAT", "TOUCH FILE", "LS",
    ])


@pytest.mark.parametrize("command", FS_COMMANDS)
def test_filesystem_commands_need_a_filesystem(session, command):
    assert session[command] == "ERROR: NO FILESYSTEM"


def test_fsstat_without_a_filesystem(session):
    assert session["FSSTAT"] == "FILESYSTEM: NOT FORMATTED"


def test_diskstat_of_the_build_image(session):
    assert session["DISKSTAT"] == "DISK:      0\nSIGNATURE: VALID\nVOLUME:    (NONE)\nBOOTABLE:  YES"


def test_format_rejects_a_long_volume_name(session):
    assert session["FORMAT TOOLONGNM"] == "ERROR: BAD NAME"


def test_enter_cancels_format(session):
    assert session.all("FORMAT")[0] == "FORMAT DISK 0? (Y/N) \nCANCELLED"      # Enter isn't echoed


def test_n_cancels_format(session):
    assert session.all("FORMAT")[1] == "FORMAT DISK 0? (Y/N) N\nCANCELLED"


def test_a_cancelled_format_changes_nothing(session):
    assert session.all("LS")[1] == "ERROR: NO FILESYSTEM"


def test_y_formats_the_disk(session):
    assert session.all("FORMAT")[2] == "FORMAT DISK 0? (Y/N) Y"
    assert session.all("LS")[2] == ""
    assert session.all("FSSTAT")[1].splitlines()[1] == "USED:       1 SECTORS (0 KB)"     # FSSTAT always says SECTORS


def test_format_keeps_the_volume_information(session):
    assert session.all("DISKSTAT")[1] == "DISK:      0\nSIGNATURE: VALID\nVOLUME:    (NONE)\nBOOTABLE:  YES"


def test_the_new_filesystem_works_and_is_valid(session):
    assert session.all("LS")[3] == "FILE"
    report = session.disks[0].check()
    assert report.ok, report
    assert report.leaks == []
    assert list(report.files) == ["/FILE"]


def test_output_follows_the_terminal_protocol(session):
    assert session.anomalies == []


# --------------------------------------------- formatting the boot disk

@pytest.fixture(scope="module")
def reformatted(boot, make_disk, host_files):
    disk = make_disk("mkdir BIN", "touch README", f"loadfile README {host_files['hello']}")
    first = boot(["CD BIN", "FORMAT SYS", Keys("Y"), "PWD", "LS", "DISKSTAT"], disks={0: disk})
    second = boot(["DISKSTAT", "LS"], disks={0: first.disks[0]})
    return first, second


def test_format_with_a_name_renames_the_volume_and_keeps_it_bootable(reformatted):
    first, _ = reformatted
    assert first["DISKSTAT"] == "DISK:      0\nSIGNATURE: VALID\nVOLUME:    SYS\nBOOTABLE:  YES"
    assert first.disks[0].volume_name == "SYS" and first.disks[0].bootable


def test_format_empties_the_disk_and_returns_to_the_root(reformatted):
    first, _ = reformatted
    assert first["PWD"] == "/"
    assert first["LS"] == ""
    assert first.disks[0].check().files == {}


def test_a_reformatted_boot_disk_still_boots(reformatted):
    _, second = reformatted
    assert "NO FILESYSTEM" not in second.boot_text
    assert second["DISKSTAT"].splitlines()[2] == "VOLUME:    SYS"
    assert second["LS"] == ""
