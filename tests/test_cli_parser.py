"""Every command's parser must build: one bad help string breaks the whole CLI,
the bar widget included."""

import asyncio
from pathlib import Path

import pytest

from quickpuff import cli
from quickpuff.cli import async_main
from quickpuff.constants import READY_ANIMATIONS, SHOWTIME_MODES
from quickpuff.paths import load_config


def test_help_builds_for_every_command(capsys):
    with pytest.raises(SystemExit) as exit_info:
        asyncio.run(async_main(["--help"]))
    assert exit_info.value.code == 0
    out = capsys.readouterr().out
    for command in ("status", "preserve", "battery", "sessions", "note", "limit", "recap", "doctor", "demo"):
        assert command in out


@pytest.mark.parametrize(
    "command",
    [
        "preserve",
        "battery",
        "sessions",
        "note",
        "limit",
        "recap",
        "qtip",
        "surprise",
        "saver",
        "demo",
        "showtime",
        "sounds",
        "overlay-screen",
    ],
)
def test_each_subcommand_help_formats(command, capsys):
    with pytest.raises(SystemExit) as exit_info:
        asyncio.run(async_main([command, "--help"]))
    assert exit_info.value.code == 0


def test_demo_sends_only_what_was_asked_and_says_what_plays(monkeypatch, capsys):
    calls = []

    async def fake_call(cmd, args=None, timeout=30.0):
        calls.append((cmd, args))
        if cmd == "demo_stop":
            return {"stopped": True}
        return {"name": "High", "preheat": 12.0, "session": 20.0, "cooldown": 6.0, "stock_peak": False}

    monkeypatch.setattr(cli, "call", fake_call)
    asyncio.run(async_main(["demo"]))
    # The daemon owns the defaults.
    assert calls[-1] == ("demo", {"notify": False, "badge": True})
    assert capsys.readouterr().out == (
        "Demo heat cycle on High: 12 s preheat, 20 s session (nothing is sent to the Peak).\n"
    )
    argv = ["demo", "--profile", "1", "--preheat", "8", "--session", "30", "--cooldown", "4", "--notify", "--no-badge"]
    asyncio.run(async_main(argv))
    assert calls[-1] == (
        "demo",
        {"notify": True, "badge": False, "profile": 1, "preheat": 8.0, "session": 30.0, "cooldown": 4.0},
    )
    capsys.readouterr()
    asyncio.run(async_main(["demo", "stop"]))
    assert calls[-1] == ("demo_stop", None)
    assert capsys.readouterr().out == "Demo stopped.\n"


def test_overlay_settings_default_to_what_the_widget_expects(capsys):
    cfg = load_config()
    assert (cfg["showtime"], cfg["sounds"], cfg["sound_volume"], cfg["overlay_screen"]) == ("corner", True, 70, "focused")
    # With no value, each says what it's set to.
    for command, shown in (("showtime", "corner"), ("sounds", "on, volume 70"), ("overlay-screen", "focused")):
        asyncio.run(async_main([command]))
        assert capsys.readouterr().out == f"{shown}\n"


@pytest.mark.parametrize("value", SHOWTIME_MODES)
def test_showtime_takes_every_mode(value, capsys):
    asyncio.run(async_main(["showtime", value]))
    assert load_config()["showtime"] == value


def test_showtime_refuses_anything_else(capsys):
    with pytest.raises(SystemExit):
        asyncio.run(async_main(["showtime", "fullscreen"]))
    assert load_config()["showtime"] == "corner"


def test_sounds_switch_and_volume_are_set_apart_and_clamped(capsys):
    asyncio.run(async_main(["sounds", "off", "--volume", "150"]))
    assert (load_config()["sounds"], load_config()["sound_volume"]) == (False, 100)
    asyncio.run(async_main(["sounds", "--volume", "-5"]))
    assert (load_config()["sounds"], load_config()["sound_volume"]) == (False, 0)
    asyncio.run(async_main(["sounds", "on"]))
    assert (load_config()["sounds"], load_config()["sound_volume"]) == (True, 0)
    assert capsys.readouterr().out.splitlines()[-1] == "Sounds on, volume 0"


def test_overlay_screen_is_focused_or_a_monitor_name(capsys):
    asyncio.run(async_main(["overlay-screen", "DP-2"]))
    assert load_config()["overlay_screen"] == "DP-2"
    asyncio.run(async_main(["overlay-screen", "HDMI-A-1"]))
    assert load_config()["overlay_screen"] == "HDMI-A-1"
    asyncio.run(async_main(["overlay-screen", "Focused"]))
    assert load_config()["overlay_screen"] == "focused"
    with pytest.raises(SystemExit):
        asyncio.run(async_main(["overlay-screen", "DP 2; reboot"]))
    assert load_config()["overlay_screen"] == "focused"


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
