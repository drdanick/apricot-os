"""The fault handler: bad disk I/O and runaway code stop the machine with a message.

A fault halts the OS, so every case needs a boot of its own. The command after
the fault checks that the shell really has stopped.
"""

import pytest

from test_tools.diskimage import DiskImage

pytestmark = pytest.mark.simulator


def run_until_fault(boot, library_programs, command, wait=3.0):
    programs = [library_programs["fault_bad_sector"], library_programs["fault_track_zero"]]
    return boot([command, "ECHO STILL RUNNING"], programs=programs, command_wait=wait)


def test_reading_a_sector_above_63_is_a_bad_segment_fault(boot, library_programs):
    result = run_until_fault(boot, library_programs, library_programs["fault_bad_sector"].run_command)
    assert "INVALID DISK IO: BAD SEGMENT #" in result.output(0).text
    assert len(result.outputs) == 1, "the shell kept running after the fault"


def test_writing_to_track_0_is_a_bad_track_fault(boot, os_build, library_programs):
    result = run_until_fault(boot, library_programs, library_programs["fault_track_zero"].run_command)
    assert "INVALID DISK IO: BAD TRACK #" in result.output(0).text
    assert len(result.outputs) == 1
    # Nothing was written: track 0 still holds the OS image.
    assert result.disks[0].sector(0, 5) == DiskImage(os_build.disk_image).sector(0, 5)


def test_running_into_empty_memory_reaches_the_runaway_handler(boot, library_programs):
    # 0x7000 is empty RAM: the CPU slides through NOPs (0x00) up to the handler at 0xFD00.
    result = run_until_fault(boot, library_programs, "MEMEXEC 7000", wait=8.0)
    assert "FLAGRANT SYSTEM ERROR" in result.output(0).text
    assert len(result.outputs) == 1
