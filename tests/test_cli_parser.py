"""Every command's parser must build: one bad help string breaks the whole CLI,
the bar widget included."""

import asyncio
from pathlib import Path

import pytest

from quickpuff.cli import async_main
from quickpuff.constants import READY_ANIMATIONS
from quickpuff.paths import load_config


def test_help_builds_for_every_command(capsys):
    with pytest.raises(SystemExit) as exit_info:
        asyncio.run(async_main(["--help"]))
    assert exit_info.value.code == 0
    out = capsys.readouterr().out
    for command in ("status", "preserve", "battery", "sessions", "note", "limit", "recap", "doctor"):
        assert command in out


@pytest.mark.parametrize("command", ["preserve", "battery", "sessions", "note", "limit", "recap", "qtip", "surprise", "saver"])
def test_each_subcommand_help_formats(command, capsys):
    with pytest.raises(SystemExit) as exit_info:
        asyncio.run(async_main([command, "--help"]))
    assert exit_info.value.code == 0


@pytest.mark.parametrize("value", READY_ANIMATIONS)
def test_ready_anim_accepts_every_animation(value, capsys):
    asyncio.run(async_main(["ready-anim", value]))
    assert load_config()["ready_animation"] == value


def test_every_ready_animation_is_playable_and_offered():
    # The overlay plays them and the panel lists them; "off" plays nothing.
    root = Path(__file__).resolve().parent.parent
    overlay = (root / "ReadyOverlay.qml").read_text()
    panel = (root / "Panel.qml").read_text()
    for value in READY_ANIMATIONS:
        assert f'"value": "{value}"' in panel
        if value != "off":
            assert f'"{value}": ' in overlay
