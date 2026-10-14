"""Command-line access to the test tools.

Run from apricot-os/tests::

    python -m test_tools build                      # build the OS and report segment use
    python -m test_tools run LS "CD BIN" PWD         # boot and type commands
    python -m test_tools run --disk 0=my.dsk --keep run/ "CAT README"
    python -m test_tools mkdisk my.dsk "mkdir BIN" "touch README" "loadfile README notes.txt"
    python -m test_tools check my.dsk --contents     # validate a disk image
    python -m test_tools render tty.out              # render captured terminal output
"""

from __future__ import annotations

import argparse
import sys
import tempfile
from pathlib import Path

from .assembler import build_os
from .config import Tools
from .diskimage import DiskImage
from .fsmanager import FsManager
from .simulator import Keys, Session, Type, Wait
from .terminal import Terminal


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="python -m test_tools", description=__doc__.split("\n\n")[0])
    parser.add_argument("--aprsim", metavar="NAME-OR-PATH", help="the simulator binary (default: $APRSIM, then aprsim)")
    parser.add_argument("--fsman", metavar="NAME-OR-PATH",
                        help="the fs-manager binary (default: $APRICOSFSMAN, then apricosfsman)")
    commands = parser.add_subparsers(dest="command", required=True)

    build = commands.add_parser("build", help="build the OS and report segment use and problems")
    build.add_argument("--out", type=Path, help="where to build (default: a temporary directory)")

    run = commands.add_parser("run", help="boot the OS and type shell commands")
    run.add_argument("steps", nargs="*", help='commands to type; "@keys:Y" types without Enter, "@wait:5" waits')
    run.add_argument("--disk", action="append", default=[], metavar="N=IMAGE", help="provide IMAGE as disk N")
    run.add_argument("--program", action="append", default=[], type=Path, metavar="BIN",
                     help="PB file to preload into memory")
    run.add_argument("--keep", type=Path, metavar="DIR", help="run in DIR and keep the disks and tty.out there")
    run.add_argument("--wait", type=float, default=1.5, help="seconds to wait after each command (default 1.5)")

    mkdisk = commands.add_parser("mkdisk", help="create a formatted disk with fs-manager")
    mkdisk.add_argument("image", type=Path)
    mkdisk.add_argument("fsman_commands", nargs="*", help='fs-manager commands, e.g. "mkdir BIN"')
    mkdisk.add_argument("--blank", action="store_true", help="a data disk with no OS image")
    mkdisk.add_argument("--volume", default="APRICOT")

    check = commands.add_parser("check", help="validate a disk image and list its files")
    check.add_argument("image", type=Path)
    check.add_argument("--contents", action="store_true", help="also print file contents")

    render = commands.add_parser("render", help="render captured port-7 output")
    render.add_argument("capture", type=Path)
    render.add_argument("--screen", action="store_true", help="only the final screen")

    args = parser.parse_args(argv)
    return globals()[f"_{args.command}"](args)


def _build(args) -> int:
    tools = Tools.from_environment(aprsim=args.aprsim, fsman=args.fsman)
    with tempfile.TemporaryDirectory() as scratch:
        result = build_os(tools, args.out or Path(scratch) / "os")
        print(f"{'unit':18}{'segments':>10}{'bytes':>8}{'room':>8}")
        for unit in result.units:
            span = f"{unit.segments.start}-{unit.segments.stop - 1}" if len(unit.segments) > 1 else str(unit.segment)
            print(f"{unit.file:18}{span:>10}{unit.size:>8}{unit.budget:>8}{'  OVERFLOW' if unit.overflows else ''}")
        for problem in result.problems:
            print(f"PROBLEM: {problem}")
        print("build OK" if not result.problems else "build has problems")
        return 1 if result.problems else 0


def _run(args) -> int:
    tools = Tools.from_environment(aprsim=args.aprsim, fsman=args.fsman)
    steps = []
    for step in args.steps:
        if step.startswith("@wait:"):
            steps.append(Wait(float(step[6:])))
        elif step.startswith("@keys:"):
            steps.append(Keys(step[6:]))
        else:
            steps.append(Type(step))
    with tempfile.TemporaryDirectory() as scratch:
        build = build_os(tools, Path(scratch) / "os")
        disks = {}
        for spec in args.disk:
            number, _, image = spec.partition("=")
            disks[int(number)] = DiskImage.load(Path(image))
        session = Session(tools, build, disks=disks, programs=[p.read_bytes() for p in args.program],
                          command_wait=args.wait, workdir=args.keep)
        result = session.run(steps)
        if args.keep:
            (args.keep / "tty.out").write_bytes(result.raw)
    print("\n".join(result.terminal.transcript))
    for anomaly in result.anomalies:
        print(f"ANOMALY: {anomaly}", file=sys.stderr)
    return 0


def _mkdisk(args) -> int:
    tools = Tools.from_environment(aprsim=args.aprsim, fsman=args.fsman)
    with tempfile.TemporaryDirectory() as scratch:
        base = None if args.blank else build_os(tools, Path(scratch) / "os").disk_image
        FsManager.from_tools(tools).create_disk(base, args.fsman_commands, volume=args.volume).save(args.image)
    print(f"wrote {args.image}")
    return 0


def _check(args) -> int:
    image = DiskImage.load(args.image)
    report = image.check()
    print(f"volume {image.volume_name!r}, {image.allocated_count} sectors allocated in tracks 1-31")
    for path, info in sorted(report.files.items()):
        flags = "fx" if info.entry.executable else "f-"
        blocks = " ".join(f"{t}/{s}" for t, s in info.blocks)
        print(f"[{flags}] {path}  {info.size} bytes  metadata {info.entry.location[0]}/{info.entry.location[1]}  blocks {blocks}")
        if args.contents:
            print(f"      {info.data!r}")
    for path in sorted(report.directories):
        print(f"[d-] {path}")
    for error in report.errors:
        print(f"ERROR: {error}")
    if report.leaks:
        print(f"WARNING: {len(report.leaks)} allocated sectors are not used by anything")
    print("filesystem OK" if report.ok else "filesystem INVALID")
    return 0 if report.ok else 1


def _render(args) -> int:
    terminal = Terminal.from_bytes(args.capture.read_bytes())
    print("\n".join(terminal.screen if args.screen else terminal.transcript))
    for anomaly in terminal.anomalies:
        print(f"ANOMALY: {anomaly}", file=sys.stderr)
    return 1 if terminal.anomalies else 0


if __name__ == "__main__":
    sys.exit(main())
