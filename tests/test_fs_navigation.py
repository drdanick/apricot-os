"""LS, CD and PWD, on prepared disks."""

import pytest

from test_tools.diskimage import OS_SECTORS, SECTOR_SIZE

pytestmark = pytest.mark.simulator

FILLER = [f"X{i:02d}" for i in range(1, 29)]      # with the four named entries below: 32, a full root


@pytest.fixture(scope="module")
def tree(make_disk, host_files):
    """A full root directory and a nested tree:

    /BIN/ (SUB/ (DEEPER/ (LEAF)), INBIN), /README, /ABCDEF*, /EMPTYD/, /X01../X28
    """
    return make_disk(
        "mkdir BIN", "touch README", f"loadfile README {host_files['hello']}",
        "touch ABCDEF", "toggleexec ABCDEF", "mkdir EMPTYD",
        "cd BIN", "mkdir SUB", "touch INBIN", "cd SUB", "mkdir DEEPER", "cd DEEPER", "touch LEAF",
        "cd ..", "cd ..", "cd ..",
        *[f"touch {name}" for name in FILLER])


@pytest.fixture(scope="module")
def session(boot, tree):
    return boot([
        "LS", "PWD",
        "CD BIN", "PWD", "LS",
        "CD SUB", "CD DEEPER", "PWD", "LS",
        "CD ..", "PWD", "CD /", "PWD", "CD ..", "PWD",
        "CD EMPTYD", "LS", "CD ..",
        "CD README", "CD NOPE", "CD", "CD TOOLONGX", "CD .", "CD A/B",
        "LS EXTRA ARGUMENT",
        "TOUCH NEW", "MKDIR NEWD", "CP README R2", "WRITE NEWF TEXT",
    ], disks={0: tree})


def test_ls_lists_the_root_in_directory_order(session):
    assert session.output(0).text.splitlines() == ["BIN/", "README", "ABCDEF*", "EMPTYD/", *FILLER]


def test_ls_marks_directories_and_executables(session):
    listing = session[0].splitlines()
    assert "BIN/" in listing and "ABCDEF*" in listing and "README" in listing


def test_pwd_at_the_root(session):
    assert session[1] == "/"


def test_cd_into_a_directory(session):
    assert session[3] == "/BIN"
    assert session[4].splitlines() == ["SUB/", "INBIN"]


def test_cd_three_levels_deep(session):
    assert session[7] == "/BIN/SUB/DEEPER"
    assert session[8] == "LEAF"


def test_cd_up(session):
    assert session[10] == "/BIN/SUB"


def test_cd_to_the_root(session):
    assert session[12] == "/"


def test_cd_up_from_the_root_stays_at_the_root(session):
    assert session[13] == ""
    assert session[14] == "/"


def test_ls_of_an_empty_directory_prints_nothing(session):
    assert session[16] == ""


@pytest.mark.parametrize("index, error", [
    (18, "NOT A DIRECTORY"),       # CD README
    (19, "NOT FOUND"),             # CD NOPE
    (20, "MISSING ARGUMENT"),      # CD
    (21, "BAD NAME"),              # CD TOOLONGX
    (22, "BAD NAME"),              # CD .
    (23, "BAD NAME"),              # CD A/B
])
def test_cd_errors(session, index, error):
    assert session[index] == f"ERROR: {error}"


def test_a_full_directory_refuses_new_entries(session):
    for command in ["TOUCH NEW", "MKDIR NEWD", "CP README R2", "WRITE NEWF TEXT"]:
        assert session[command] == "ERROR: DIRECTORY FULL", command


def test_ls_ignores_its_argument(session):
    assert session["LS EXTRA ARGUMENT"] == session[0]


def test_navigation_and_refused_commands_do_not_change_the_disk(session, tree):
    filesystem = OS_SECTORS * SECTOR_SIZE          # everything after the OS image
    assert session.disks[0].data[filesystem:] == tree.data[filesystem:]


def test_output_follows_the_terminal_protocol(session):
    assert session.anomalies == []


@pytest.fixture(scope="module")
def deep_session(boot, make_disk):
    """CD down a chain of 16 nested directories: the path stack holds 15 below the root."""
    commands = []
    for level in range(1, 17):
        commands += [f"mkdir D{level}", f"cd D{level}"]
    disk = make_disk(*commands)
    return boot([*(f"CD D{level}" for level in range(1, 17)), "PWD", "CD ..", "PWD"],
                disks={0: disk}, command_wait=1.0)


def test_path_too_deep(deep_session):
    assert deep_session["CD D15"] == ""
    assert deep_session["CD D16"] == "ERROR: PATH TOO DEEP"
    assert deep_session.all("PWD") == ["/" + "/".join(f"D{i}" for i in range(1, 16)),
                                       "/" + "/".join(f"D{i}" for i in range(1, 15))]
