"""Booting and the shell's built-in commands, on the plain build image (no filesystem)."""

import pytest

from test_tools.simulator import DELETE

pytestmark = pytest.mark.simulator

LONG_INPUT = "ECHO " + "X" * 130      # more than the 128-character input buffer


@pytest.fixture(scope="module")
def session(boot):
    return boot([
        "HELP",
        "HI",
        "ECHO HELLO WORLD",
        "ECHO",
        "echo lower case",
        "NOSUCHCMD",
        "",
        "ECHO AB" + DELETE.decode() + "C",
        LONG_INPUT,
        "MEMEXEC 3D00",
        "ECHO A\tB",
        "CLS",
    ])


def test_boot_messages(session):
    for message in ["Loading Operating System", "Booting ApricotOS", "Welcome to ApricotOS!",
                    "ApricotOS PIE shell [Version 0.0.1]", "(C) Copyright 2014-2018 Nick Stones-Havas"]:
        assert message in session.boot_text


def test_boot_without_a_filesystem_prints_a_notice(session):
    assert session.boot_text.rstrip().endswith("NO FILESYSTEM - TYPE FORMAT")


def test_help_lists_every_command(session):
    assert session["HELP"].splitlines() == [
        "KNOWN COMMANDS:", "HI", "CD", "LS", "CP", "STAT", "MV", "RM", "PWD", "CLS", "CAT", "ECHO",
        "TOUCH", "MKDIR", "WRITE", "MEMEXEC", "FORMAT", "FSSTAT", "DISKSEL", "DISKSTAT", "HELP"]


def test_hi(session):
    assert session["HI"] == "Hello Sailor..."


def test_echo(session):
    assert session["ECHO HELLO WORLD"] == "HELLO WORLD"


def test_echo_without_an_argument_prints_nothing(session):
    assert session["ECHO"] == ""


def test_input_is_uppercased(session):
    """Lowercase letters are echoed as typed, but the command runs uppercased."""
    assert session.outputs[4].command == "echo lower case"
    assert session[4] == "LOWER CASE"


def test_unknown_command(session):
    assert session["NOSUCHCMD"] == "BAD COMMAND OR FILENAME"


def test_empty_line_does_nothing(session):
    assert session.outputs[6].command == ""
    assert session[6] == ""


def test_backspace_edits_the_line(session):
    assert session["ECHO AC"] == "AC"


def test_input_is_limited_to_128_characters(session):
    long_command = session.outputs[8]
    assert long_command.command == LONG_INPUT[:128]
    assert long_command.text == "X" * 123


def test_control_characters_are_dropped_from_input(session):
    assert session["ECHO AB"] == "AB"          # the tab was never stored or echoed


def test_memexec_runs_the_test_program(session):
    assert session["MEMEXEC 3D00"] == "Hello! You have just executed ApricotOS' first program!"


def test_cls_clears_the_screen(session):
    """After CLS, only the next prompt is on screen (the prompt starts with a newline)."""
    assert session.terminal.screen == ["", ">"]


def test_output_follows_the_terminal_protocol(session):
    assert session.anomalies == []
    assert session.terminal.in_print_mode
