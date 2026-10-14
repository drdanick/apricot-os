"""The OS library routines, exercised by the test programs in tests/programs.

All the programs are loaded before one boot and run with MEMEXEC. Expected
values are computed here in Python. Known bugs are marked ``xfail`` with
``strict=True``, so fixing one makes its test fail until the mark is removed.
"""

import pytest

from test_tools.programs import parse_results, results_named

pytestmark = pytest.mark.simulator

FREE_FOR_ALLOCATOR = [(1, 7), (25, 2), (31, 63)]
BULK_READ_VALUES = [0x11, 0x22, 0x33, 0x44]
PROGRAMS = ["test_memutil", "test_math", "test_disp", "test_osutil", "test_diskio", "test_diskalloc"]


@pytest.fixture(scope="module")
def session(boot, make_disk, library_programs):
    disk = make_disk()
    disk.fill_free_space()                     # leave exactly three free sectors for the allocator test
    for track, sector in FREE_FOR_ALLOCATOR:
        disk.set_allocated(track, sector, False)
    for sector, value in zip(range(8, 12), BULK_READ_VALUES):     # read by COPYBULKFROMDSK
        disk.write_sector(30, sector, bytes([value]) * 256)
    programs = [library_programs[name] for name in ["testlib", *PROGRAMS]]
    steps = [library_programs[name].run_command for name in PROGRAMS]
    return boot(steps, disks={0: disk}, programs=programs, command_wait=5)


def output_of(session, programs, name):
    return session[programs[name].run_command]


@pytest.fixture(scope="module")
def outputs(session, library_programs):
    return {name: output_of(session, library_programs, name) for name in PROGRAMS}


def test_output_follows_the_terminal_protocol(session):
    assert session.anomalies == []


# ----------------------------------------------------------------- memutil

class TestMemutil:
    def test_segset(self, outputs):
        assert results_named(outputs["test_memutil"], "SEGSET") == [[0xAB, 0xAB]]

    def test_segcpy(self, outputs):
        assert results_named(outputs["test_memutil"], "SEGCPY") == [[0xAB, 0xAB]]

    def test_memset_across_a_page_boundary(self, outputs):
        # untouched before, set from 0x70F0 to 0x710F, untouched after
        assert results_named(outputs["test_memutil"], "MEMSET") == [[0xAB, 0x5A, 0x5A, 0xAB]]

    def test_memcpy_across_a_page_boundary(self, outputs):
        assert results_named(outputs["test_memutil"], "MEMCPY") == [list(b"HELLO\0")]

    def test_strlen_across_a_page_boundary(self, outputs):
        assert results_named(outputs["test_memutil"], "STRLEN") == [[5]]

    def test_memcmp(self, outputs):
        equal, different = results_named(outputs["test_memutil"], "MEMCMP")[0]
        assert equal != 0 and different == 0

    def test_strcmp(self, outputs):
        same, shorter, different = results_named(outputs["test_memutil"], "STRCMP")[0]
        assert same != 0 and shorter == 0 and different == 0


# -------------------------------------------------------------------- math

MULT_CASES = [(7, 6), (1, 200), (2, 200), (16, 16), (0, 255), (255, 1), (15, 17)]
FASTMULT_CASES = [(7, 6), (12, 10), (85, 3), (0, 9)]
DIV_CASES = [(100, 7), (200, 7), (128, 1), (0, 5), (127, 127), (250, 3), (9, 10)]
POW_CASES = [(2, 7), (3, 6), (5, 0), (129, 2), (2, 8)]


class TestMath:
    def test_mult(self, outputs):
        expected = [[a, b, (a * b) & 0xFF, int(a * b > 0xFF)] for a, b in MULT_CASES]
        assert results_named(outputs["test_math"], "MULT") == expected

    def test_fastmult(self, outputs):
        expected = [[a, b, (a * b) & 0xFF] for a, b in FASTMULT_CASES]
        assert results_named(outputs["test_math"], "FASTMULT") == expected

    def test_div(self, outputs):
        expected = [[a, b, *divmod(a, b)] for a, b in DIV_CASES]
        assert results_named(outputs["test_math"], "DIV") == expected

    def test_pow(self, outputs):
        expected = [[a, b, (a ** b) & 0xFF, int(a ** b > 0xFF)] for a, b in POW_CASES]
        assert results_named(outputs["test_math"], "POW") == expected

    @pytest.mark.parametrize("index, text, value", [
        (0, "123", 123),
        pytest.param(1, "7", 7, marks=pytest.mark.xfail(strict=True, reason=(
            "ATOB bug: the length check pops the decimal weight instead of the length, "
            "so one-digit strings are rejected"))),
        (2, "255", 255),
        pytest.param(3, "0", 0, marks=pytest.mark.xfail(strict=True, reason="ATOB one-digit bug, as above")),
    ])
    def test_atob(self, outputs, index, text, value):
        assert results_named(outputs["test_math"], "ATOB")[index] == [1, value], text

    def test_htoi(self, outputs):
        assert results_named(outputs["test_math"], "HTOI") == [[0x1A, 0x2B], [0x00, 0x0F], [0x00, 0x00], [0xFF, 0xFF]]

    def test_rand_is_an_8_bit_xorshift(self, outputs):
        def sequence(seed, count):
            values = []
            for _ in range(count):
                seed ^= (seed << 3) & 0xFF
                seed ^= seed >> 5
                seed ^= (seed << 4) & 0xFF
                values.append(seed)
            return values
        assert results_named(outputs["test_math"], "RAND") == [sequence(1, 5), sequence(0x5A, 3)]


# -------------------------------------------------------------------- disp

def putnum_lines(text):
    """{value: printed text} for the PUTNUM lines."""
    return {int(tokens[0], 16): tokens[1] if len(tokens) > 1 else "" for name, tokens in parse_results(text)
            if name == "PUTNUM"}


class TestDisp:
    @pytest.mark.parametrize("value", [
        0, 7, 42, 99, 255,
        pytest.param(100, marks=pytest.mark.xfail(strict=True, reason="PUTNUM drops a zero tens digit")),
        pytest.param(105, marks=pytest.mark.xfail(strict=True, reason="PUTNUM drops a zero tens digit")),
        pytest.param(200, marks=pytest.mark.xfail(strict=True, reason="PUTNUM drops a zero tens digit")),
    ])
    def test_putnum(self, outputs, value):
        assert putnum_lines(outputs["test_disp"])[value] == str(value)

    def test_putnum16(self, outputs):
        printed = {(int(t[0], 16) << 8) | int(t[1], 16): t[2]
                   for name, t in parse_results(outputs["test_disp"]) if name == "PUTNUM16"}
        assert printed == {v: str(v) for v in [9, 10, 99, 100, 1000, 1004, 1984, 10000, 32512, 65535, 0]}

    def test_putstr_across_a_page_boundary(self, outputs):
        assert ("PUTSTR", ["ABCDEFGH"]) in parse_results(outputs["test_disp"])


# ------------------------------------------------------------------ osutil

class TestOsutil:
    def test_pushregs_and_popregs_restore_a0_to_a7(self, outputs):
        assert results_named(outputs["test_osutil"], "PUSHREGS") == [list(range(0x10, 0x18))]

    def test_push_and_pop_volatile_regs_restore_a8_to_a14(self, outputs):
        assert results_named(outputs["test_osutil"], "PUSHVOLATILEREGS") == [list(range(0x28, 0x2F))]

    def test_push_and_pop_all_regs_restore_a0_to_a14(self, outputs):
        assert results_named(outputs["test_osutil"], "PUSHALLREGS") == [list(range(0x30, 0x3F))]

    def test_pushregsandcopy_copies_a8_to_a14(self, outputs):
        assert results_named(outputs["test_osutil"], "PUSHREGSANDCOPY") == [list(range(0x58, 0x5F))]
        assert results_named(outputs["test_osutil"], "RESTORED") == [list(range(0x40, 0x48))]


# ------------------------------------------------------------------ diskio

BULK_BUG = ("COPYBULKTODSK applies its sector-wrap check to the memory segment, not the disk "
            "sector, so a source at 0x70 or above jumps to memory segment 0 and the next track")


class TestDiskio:
    def test_copytodsk_and_copyfromdsk(self, session, outputs):
        assert results_named(outputs["test_diskio"], "COPY") == [[0xC3, 0xC3]]
        assert session.disks[0].sector(28, 40) == bytes([0xC3]) * 256

    @pytest.mark.xfail(strict=True, reason=BULK_BUG)
    def test_copybulktodsk(self, session):
        disk = session.disks[0]
        assert [disk.sector(30, s) for s in range(2, 6)] == [bytes([v]) * 256 for v in (0x11, 0x22, 0x33, 0x44)]

    def test_copybulkfromdsk(self, outputs):
        assert results_named(outputs["test_diskio"], "BULK") == [BULK_READ_VALUES]

    @pytest.mark.xfail(strict=True, reason="bulk copies wrap tracks after 16 sectors (mask 0x70, not 0xC0)")
    def test_copybulktodsk_past_sector_15(self, session):
        disk = session.disks[0]
        assert [disk.sector(29, s)[0] for s in (14, 15, 16)] == [0x77, 0x88, 0x99]


# --------------------------------------------------------------- diskalloc

class TestDiskalloc:
    def test_allocates_first_fit_until_the_disk_is_full(self, outputs):
        allocations = results_named(outputs["test_diskalloc"], "ALLOC")
        assert allocations[:4] == [[0, 1, 7], [0, 25, 2], [0, 31, 63], [6]]

    def test_free_then_check(self, outputs):
        freed_sector, root = results_named(outputs["test_diskalloc"], "CHECK")[0]
        assert freed_sector == 0 and root != 0

    def test_freed_sector_is_reused(self, outputs):
        assert results_named(outputs["test_diskalloc"], "ALLOC")[4] == [0, 25, 2]

    def test_flush_writes_the_bitmap(self, session):
        assert session.disks[0].free_sectors() == []
