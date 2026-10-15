"""The stage 1 boot loader (boot.asm): it boots only a valid, bootable disk 0.

The loader selects disk 0 (three tries), then checks the volume information
sector (track 0, sector 63): the disk signature in bytes 0-3, then the boot
flag ``AA 55`` in bytes 254-255. A failed check prints a message and halts.

Each case is a boot of its own. A command typed after the boot checks that
the shell never started.
"""

import pytest

from test_tools.diskimage import DiskImage, VOLUME_SECTOR

pytestmark = pytest.mark.simulator

READ_ERROR = "Disk read error!"
NOT_VALID = "Disk 0 not valid!"
NOT_BOOTABLE = "Disk 0 not bootable!"
LOADING = "Loading Operating System..."

# What the loader sends first: end any command, clear the screen, select
# foreground colour 2, then repeat-PUTC mode.
TTY_SETUP = bytes([0x03, 0x12, 0x12, 0x0C, 0x02, 0x7F, 0x00])

# Signatures that must be rejected. Every byte position is wrong in one case;
# FF 00 00 00 and 03 0C 30 C0 XOR to 0xFF like the real signature.
BAD_SIGNATURES = [
    "00 00 00 00", "C1 30 0C 03", "C0 31 0C 03", "C0 30 0D 03", "C0 30 0C 07",
    "FF 00 00 00", "03 0C 30 C0",
]

# Boot flags that must be rejected. The loader checks a ^ b == 0xFF (passed by
# 00 FF, 2A D5, 55 AA, D5 2A) and b ^ (b << 1) == 0xFF (passed by AB 55), so
# neither check is enough on its own.
BAD_BOOT_FLAGS = ["00 00", "00 FF", "AA 54", "AB 55", "AB 54", "55 AA", "2A D5", "D5 2A", "FF FF"]


def patched(image: DiskImage, offset: int, hex_bytes: str) -> DiskImage:
    """A copy of ``image`` with ``hex_bytes`` written at ``offset`` of the volume information sector."""
    disk = image.copy()
    start = DiskImage.offset(0, VOLUME_SECTOR) + offset
    data = bytes.fromhex(hex_bytes)
    disk.data[start:start + len(data)] = data
    return disk


@pytest.fixture(scope="module")
def build_disk(os_build) -> DiskImage:
    return DiskImage(os_build.disk_image)


@pytest.fixture
def boot_disk(boot):
    """``boot_disk(disks)``: boot, type one command, and return the session."""
    def run(disks):
        return boot(["ECHO SHELL RUNNING"], disks=disks)
    return run


@pytest.fixture
def boot_halting(boot):
    """``boot_halting(disks)``: boot a disk the loader rejects, type one key, and return the session.

    The loader gives up within about 3 s (three tries at selecting disk 0, a
    second apart), and the shell would have printed its prompt by then.
    """
    def run(disks):
        return boot(["X"], disks=disks, boot_wait=4.0, command_wait=0.5)
    return run


def assert_halted_with(result, message):
    """The loader printed only ``message``, and nothing ran after it."""
    assert result.raw == TTY_SETUP + message.encode()


def test_a_valid_bootable_disk_boots(boot_disk, build_disk):
    result = boot_disk({0: build_disk})
    assert result.raw.startswith(TTY_SETUP + LOADING.encode())
    assert result["ECHO SHELL RUNNING"] == "SHELL RUNNING"


def test_no_disk_0_is_a_read_error(boot_halting, build_disk):
    # Disk 1 exists, but the loader only ever boots disk 0.
    assert_halted_with(boot_halting({1: build_disk}), READ_ERROR)


@pytest.mark.parametrize("signature", BAD_SIGNATURES)
def test_a_bad_signature_is_not_valid(boot_halting, build_disk, signature):
    assert_halted_with(boot_halting({0: patched(build_disk, 0, signature)}), NOT_VALID)


def test_the_signature_is_checked_before_the_boot_flag(boot_halting, build_disk):
    disk = patched(patched(build_disk, 0, "00 00 00 00"), 254, "00 00")
    assert_halted_with(boot_halting({0: disk}), NOT_VALID)


@pytest.mark.parametrize("flag", BAD_BOOT_FLAGS)
def test_a_bad_boot_flag_is_not_bootable(boot_halting, build_disk, flag):
    assert_halted_with(boot_halting({0: patched(build_disk, 254, flag)}), NOT_BOOTABLE)


@pytest.fixture(scope="module")
def diskstat_session(boot, build_disk):
    """DISKSTAT of disks 1-7, each with a different boot flag."""
    flags = ["AA 55", "00 FF", "AB 54", "AA 54", "2A D5", "55 AA", "FF FF"]
    disks = {0: build_disk}
    steps = []
    for number, flag in enumerate(flags, start=1):
        disks[number] = patched(build_disk, 254, flag)
        steps += [f"DISKSEL {number}", "DISKSTAT"]
    return flags, boot(steps, disks=disks)


def test_diskstat_reports_the_boot_flag_exactly(diskstat_session):
    flags, result = diskstat_session
    reported = [text.splitlines()[-1] for text in result.all("DISKSTAT")]
    expected = [f"BOOTABLE:  {'YES' if flag == 'AA 55' else 'NO'}" for flag in flags]
    assert reported == expected


@pytest.fixture(scope="module")
def signature_session(boot, build_disk):
    """DISKSEL and DISKSTAT of disks 1-7, each with a bad signature, then disk 8 with the real one."""
    disks = {0: build_disk, 8: build_disk}
    steps = []
    for number, signature in enumerate(BAD_SIGNATURES, start=1):
        disks[number] = patched(build_disk, 0, signature)
        steps += [f"DISKSEL {number}", "DISKSTAT"]
    steps += ["DISKSEL 8", "DISKSTAT"]
    return boot(steps, disks=disks)


def test_the_driver_checks_the_signature_exactly(signature_session):
    # The filesystem driver's mount (FS_MOUNT_DISK) makes the same check as the loader.
    reported = [text.splitlines()[1] for text in signature_session.all("DISKSTAT")]
    expected = ["SIGNATURE: INVALID"] * len(BAD_SIGNATURES) + ["SIGNATURE: VALID"]
    assert reported == expected
