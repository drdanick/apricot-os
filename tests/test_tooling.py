"""Unit tests for the test tooling itself (no simulator needed)."""


import pytest

from test_tools.assembler import find_cross_page_local_calls, find_page_end_branches, read_pb, units_from_assemble_script
from test_tools.config import ASSEMBLE_SCRIPT
from test_tools.diskimage import IMAGE_SIZE, ROOT, VOLUME_SECTOR, DiskImage
from test_tools.programs import parse_results, results_named
from test_tools.terminal import CLEAR_MARKER, Terminal

PRINT = b"\x7f\x00"          # repeat mode on PUTC: everything after is text


class TestTerminal:
    def test_prints_text_in_repeat_print_mode(self):
        terminal = Terminal.from_bytes(PRINT + b"HELLO\nWORLD")
        assert terminal.screen == ["HELLO", "WORLD"]
        assert terminal.text == "HELLO\nWORLD"
        assert terminal.in_print_mode
        assert not terminal.anomalies

    def test_backspace_removes_the_last_character(self):
        terminal = Terminal.from_bytes(PRINT + b"ABX\x08C")
        assert terminal.screen == ["ABC"]
        assert terminal.text == "ABC"

    def test_long_lines_wrap_on_screen_but_not_in_text(self):
        terminal = Terminal.from_bytes(PRINT + b"X" * 85)
        assert terminal.screen == ["X" * 80, "X" * 5]
        assert terminal.text == "X" * 85

    def test_scrolled_lines_are_kept_in_the_transcript(self):
        terminal = Terminal.from_bytes(PRINT + b"".join(b"%d\n" % i for i in range(40)))
        assert terminal.transcript[0] == "0"
        assert terminal.screen[0] != "0"

    def test_clear_screen(self):
        terminal = Terminal.from_bytes(PRINT + b"OLD\x03\x12\x12" + PRINT + b"NEW")
        assert terminal.screen == ["NEW"]
        assert CLEAR_MARKER in terminal.transcript
        assert "OLD" in terminal.transcript

    def test_text_after_end_of_message_is_an_anomaly(self):
        terminal = Terminal.from_bytes(PRINT + b"A\x03B")
        assert terminal.screen == ["A"]
        assert any("outside print mode" in str(a) for a in terminal.anomalies)

    def test_non_printable_glyph_is_an_anomaly(self):
        terminal = Terminal.from_bytes(PRINT + b"\x01")
        assert terminal.anomalies

    def test_cursor_commands(self):
        # set row 2, set column 5, then print
        terminal = Terminal.from_bytes(b"\x0e\x02\x0f\x05" + PRINT + b"X")
        assert terminal.screen == ["", "", "     X"]


class TestDiskImage:
    def test_blank_image(self):
        image = DiskImage()
        assert len(image.data) == IMAGE_SIZE
        assert not image.has_signature

    def test_rejects_wrong_size(self):
        with pytest.raises(ValueError):
            DiskImage(b"\0" * 100)

    def test_bitmap(self):
        image = DiskImage()
        image.set_allocated(25, 2)
        assert image.is_allocated(25, 2)
        assert image.data[DiskImage.offset(0, 62) + 200] == 0b100
        image.set_allocated(25, 2, False)
        assert not image.is_allocated(25, 2)

    def test_fill_free_space_leaves_the_first_sectors(self):
        image = _formatted()
        left = image.fill_free_space(leave_free=2)
        assert left == [(1, 1), (1, 2)]
        assert image.free_sectors() == left

    def test_check_accepts_an_empty_filesystem(self):
        report = _formatted().check()
        assert report.ok, report
        assert list(report.directories) == ["/"]

    def test_check_finds_a_file_and_its_data(self):
        image = _formatted()
        _add_file(image, "NOTE", metadata=(1, 1), blocks=[(1, 2)], data=b"hi\n")
        report = image.check()
        assert report.ok, report
        assert report.files["/NOTE"].data == b"hi\n"
        assert report.files["/NOTE"].blocks == [(1, 2)]

    def test_check_reports_a_sector_used_twice(self):
        image = _formatted()
        _add_file(image, "A", metadata=(1, 1), blocks=[(1, 3)], data=b"a")
        _add_file(image, "B", metadata=(1, 2), blocks=[(1, 3)], data=b"b", slot=1)
        assert any("also used by" in e for e in image.check().errors)

    def test_check_reports_an_unallocated_reference(self):
        image = _formatted()
        _add_file(image, "A", metadata=(1, 1), blocks=[(1, 2)], data=b"a")
        image.set_allocated(1, 2, False)
        assert any("free in the bitmap" in e for e in image.check().errors)

    def test_check_reports_leaks(self):
        image = _formatted()
        image.set_allocated(5, 5)
        report = image.check()
        assert report.ok
        assert report.leaks == [(5, 5)]

    def test_check_reports_a_size_that_does_not_match_the_blocks(self):
        image = _formatted()
        _add_file(image, "A", metadata=(1, 1), blocks=[(1, 2)], data=b"a" * 300)
        assert any("blocks for" in e for e in image.check().errors)


class TestAssemblerHelpers:
    def test_read_pb(self):
        assert read_pb(b"PB\x02\x00\x00\x40\xAA\xBB") == (0x4000, b"\xAA\xBB")

    def test_unit_list_comes_from_assemble_sh(self):
        units = units_from_assemble_script(ASSEMBLE_SCRIPT)
        assert "fsdriver.asm" in units and "testprogram.asm" in units
        assert "boot.asm" not in units

    def test_page_end_branch_detection(self):
        # 0xFE NOPs, then BRp 0x00 at offset 0xFE of page 0x40
        program = b"PB" + bytes([0x00, 0x01, 0x00, 0x40]) + b"\x00" * 0xFE + b"\xC3\x00"
        assert find_page_end_branches(program, {}) == ["0x40fe (after label ?)"]

    def test_cross_page_local_call_detection(self, tmp_path):
        source = tmp_path / "unit.asm"
        source.write_text("#segment 0x40\nSTART:\n    OS_LOCALSYSCALL FAR\n")
        symbols = {"start": [0x4000], "far": [0x4100]}
        assert len(find_cross_page_local_calls(source, symbols)) == 1
        symbols["far"] = [0x4080]
        assert find_cross_page_local_calls(source, symbols) == []


def test_parse_results():
    text = "MULT 07 06 2A 00\nPUTSTR ABC\nMULT 01 02 02 00"
    assert parse_results(text)[1] == ("PUTSTR", ["ABC"])
    assert results_named(text, "MULT") == [[7, 6, 0x2A, 0], [1, 2, 2, 0]]


# Helpers

def _formatted() -> DiskImage:
    image = DiskImage()
    image.write_sector(0, VOLUME_SECTOR, bytes([0xC0, 0x30, 0x0C, 0x03]) + bytes(252))
    for sector in range(64):
        image.set_allocated(0, sector)
    image.set_allocated(*ROOT)
    return image


def _add_file(image, name, metadata, blocks, data, slot=0):
    directory = bytearray(image.sector(*ROOT))
    directory[slot * 8:slot * 8 + 8] = bytes([0xA0 | metadata[0], metadata[1]]) + name.encode().ljust(6, b"\0")
    image.write_sector(*ROOT, bytes(directory))
    meta = bytearray(256)
    meta[0], meta[1] = len(data) & 0xFF, len(data) >> 8
    for index, (track, sector) in enumerate(blocks):
        meta[2 + 2 * index], meta[3 + 2 * index] = track, sector
        image.set_allocated(track, sector)
        chunk = data[index * 256:(index + 1) * 256]
        image.write_sector(track, sector, chunk.ljust(256, b"\0"))
    image.set_allocated(*metadata)
    image.write_sector(*metadata, bytes(meta))
