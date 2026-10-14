"""The OS builds cleanly and its image has the expected layout."""

from test_tools.assembler import FIRST_UNLOADED_SEGMENT, read_pb, units_from_assemble_script
from test_tools.config import ASSEMBLE_SCRIPT, OS_SOURCES
from test_tools.diskimage import IMAGE_SIZE, SIGNATURE, DiskImage


def test_build_has_no_problems(os_build):
    assert os_build.problems == []


def test_every_unit_fits_in_its_segments(os_build):
    for unit in os_build.units:
        assert not unit.overflows, f"{unit.file}: {unit.size} bytes, room for {unit.budget}"


def test_units_are_loaded_at_boot(os_build):
    """Stage 2 loads segments 1-61; anything higher would also overwrite disk sectors 62/63."""
    for unit in os_build.units:
        assert unit.segments.stop <= FIRST_UNLOADED_SEGMENT, unit


def test_no_two_units_share_a_segment(os_build):
    used = {}
    for unit in os_build.units:
        for segment in unit.segments:
            assert segment not in used, f"{unit.file} and {used[segment]} both use segment {segment}"
            used[segment] = unit.file


def test_every_source_unit_is_built(os_build):
    """Every .asm file with a #segment, except the stage 1 loader, is in assemble.sh."""
    built = set(units_from_assemble_script(ASSEMBLE_SCRIPT))
    for source in OS_SOURCES.glob("*.asm"):
        if source.name != "boot.asm" and "#segment" in source.read_text():
            assert source.name in built, f"{source.name} is not in assemble.sh"


def test_disk_image_layout(os_build):
    image = DiskImage(os_build.disk_image)
    assert len(os_build.disk_image) == IMAGE_SIZE
    assert image.sector(0, 62)[:4] == SIGNATURE
    assert image.bootable
    # The assembler's image has no filesystem: the bitmap and root are empty.
    assert not any(image.sector(0, 63))


def test_boot_loader_is_a_pb_file_at_address_0(os_build):
    origin, code = read_pb(os_build.boot_image)
    assert origin == 0
    assert 0 < len(code) <= 256


def test_test_program_is_at_0x3d00(os_build):
    """The shell's MEMEXEC example and the docs use address 0x3D00."""
    assert os_build.unit("testprogram.asm").segment == 0x3D
