"""The command-line interface (python -m test_tools), without the simulator."""

import os
import subprocess
import sys

import pytest

from test_tools.config import TESTS_DIR
from test_tools.diskimage import DiskImage


@pytest.fixture
def run_cli(tools):
    """Run ``python -m test_tools`` with the same tools as this test run (``--aprsim``/``--fsman``)."""
    environment = dict(os.environ)
    for variable, chosen in (("APRSIM", tools.aprsim), ("APRICOSFSMAN", tools.fsman)):
        if chosen:
            environment[variable] = chosen

    def run(*arguments):
        return subprocess.run([sys.executable, "-m", "test_tools", *map(str, arguments)],
                              cwd=TESTS_DIR, capture_output=True, text=True, env=environment)
    return run


def test_build_reports_every_unit(tools, run_cli):
    result = run_cli("build")
    assert result.returncode == 0, result.stdout + result.stderr
    assert "fsdriver.asm" in result.stdout and result.stdout.rstrip().endswith("build OK")


def test_check_validates_a_disk(make_disk, host_files, tmp_path, run_cli):
    image = make_disk("touch HELLO", f"loadfile HELLO {host_files['hello']}").save(tmp_path / "ok.dsk")
    result = run_cli("check", image, "--contents")
    assert result.returncode == 0
    assert "/HELLO  16 bytes" in result.stdout and "Hello, Apricot!" in result.stdout


def test_check_fails_on_a_broken_disk(tmp_path, run_cli):
    result = run_cli("check", DiskImage().save(tmp_path / "blank.dsk"))
    assert result.returncode == 1
    assert "ERROR: no disk signature" in result.stdout


def test_render_replays_terminal_output(tmp_path, run_cli):
    capture = tmp_path / "tty.out"
    capture.write_bytes(b"\x7f\x00HELLO\nWORLD")
    result = run_cli("render", capture)
    assert result.returncode == 0
    assert result.stdout.splitlines() == ["HELLO", "WORLD"]


def test_mkdisk_creates_a_bootable_formatted_disk(fs_manager, tmp_path, run_cli):
    image = tmp_path / "new.dsk"
    result = run_cli("mkdisk", image, "mkdir BIN")
    assert result.returncode == 0, result.stdout + result.stderr
    disk = DiskImage.load(image)
    assert disk.bootable and "/BIN/" in disk.check().directories
