"""The CLI side of the hardening: --no-start, the ui block it reads itself,
settings that can't be saved, and the debug daemon it can start."""

import asyncio
import json

import pytest

from quickpuff import cli, paths
from quickpuff.cli import async_main


@pytest.fixture
def never_start(monkeypatch):
    def refuse(*_a, **_k):
        raise AssertionError("--no-start started the daemon")

    monkeypatch.setattr(cli, "ensure_daemon", refuse)


def test_no_start_never_starts_the_daemon_and_says_it_isnt_running(never_start):
    with pytest.raises(SystemExit) as info:
        asyncio.run(async_main(["--no-start", "status"]))
    message = info.value.code
    assert isinstance(message, str) and "daemon is not running" in message.lower()


def test_no_start_treats_a_stale_socket_as_not_running(never_start):
    import socket

    path = paths.socket_path()
    stale = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    stale.bind(str(path))
    stale.close()  # left behind by a daemon that was killed
    with pytest.raises(SystemExit) as info:
        asyncio.run(async_main(["--no-start", "--json", "status"]))
    assert "daemon is not running" in str(info.value.code).lower()


def test_waybar_with_no_start_and_no_daemon_still_prints_its_json(never_start, capsys):
    paths.save_config({"units": "C"})
    assert asyncio.run(async_main(["--no-start", "waybar"])) == 0
    out = json.loads(capsys.readouterr().out)
    assert out["class"] == "disconnected" and out["text"] == "Peak"
    assert out["ui"]["units"] == "C"


def test_without_no_start_the_daemon_is_started(monkeypatch):
    started = []
    monkeypatch.setattr(cli, "ensure_daemon", lambda: started.append(True))

    async def fake_rpc(cmd, args=None, timeout=30.0):
        return {"connected": False}

    monkeypatch.setattr(cli, "rpc", fake_rpc)
    asyncio.run(async_main(["--json", "status"]))
    assert started == [True]


def test_no_start_is_in_the_help(capsys):
    with pytest.raises(SystemExit):
        asyncio.run(async_main(["--help"]))
    assert "--no-start" in capsys.readouterr().out


# ---- the ui block -------------------------------------------------------------------


def test_json_status_carries_the_clis_own_ui_over_the_daemons(monkeypatch, capsys):
    paths.save_config({"units": "C", "ready_animation": "neon"})

    async def fake_call(cmd, args=None, timeout=30.0):
        # An older daemon sends none; a confused one could send anything.
        return {"connected": False, "ui": {"units": "F", "ready_animation": "<b>"}}

    monkeypatch.setattr(cli, "call", fake_call)
    asyncio.run(async_main(["--json", "status"]))
    out = json.loads(capsys.readouterr().out)
    assert out["ui"] == paths.ui_settings()
    assert out["ui"]["units"] == "C" and out["ui"]["ready_animation"] == "neon"


def test_waybar_carries_the_ui_block_and_uses_its_units(monkeypatch, capsys):
    paths.save_config({"units": "C", "overlay_screen": "HDMI-A-1"})
    cli.print_waybar({"connected": True, "battery": 80, "heater_temp_c": 260.4, "heater_temp_f": 500})
    out = json.loads(capsys.readouterr().out)
    assert out["text"].startswith("260°C")
    assert out["ui"] == paths.ui_settings()
    assert set(out) == {"text", "tooltip", "class", "alt", "percentage", "ui"}


# ---- settings that can't be saved ---------------------------------------------------


@pytest.mark.parametrize(
    "argv",
    [["units", "C"], ["showtime", "stage"], ["ready-anim", "lava"], ["sounds", "off"], ["overlay-screen", "DP-2"]],
)
def test_a_refused_config_is_said_plainly_and_left_alone(tmp_path, argv):
    victim = tmp_path / "victim.txt"
    victim.write_text("must survive\n")
    path = paths.config_path()
    path.parent.mkdir(parents=True)
    path.symlink_to(victim)
    with pytest.raises(SystemExit) as info:
        asyncio.run(async_main(argv))
    assert str(info.value.code).startswith("Settings not saved:")
    assert victim.read_text() == "must survive\n"
    assert path.is_symlink()


def test_monitor_names_are_held_to_what_the_shell_accepts():
    asyncio.run(async_main(["overlay-screen", "A" * 32]))
    assert paths.load_config()["overlay_screen"] == "A" * 32
    with pytest.raises(SystemExit):
        asyncio.run(async_main(["overlay-screen", "A" * 33]))


# ---- the debug daemon -----------------------------------------------------------------


def test_quickpuff_daemon_hands_its_own_options_to_the_daemon(monkeypatch):
    from quickpuff import daemon

    seen = []
    monkeypatch.setattr(daemon, "main", lambda argv=None: seen.append(argv))
    cli.main(["daemon", "--debug"])
    assert seen == [["--debug"]]


def test_peek_and_poke_help_says_they_need_a_debug_daemon(capsys):
    for command in ("peek", "poke"):
        with pytest.raises(SystemExit):
            asyncio.run(async_main([command, "--help"]))
    with pytest.raises(SystemExit):
        asyncio.run(async_main(["--help"]))
    assert capsys.readouterr().out.count("--debug") >= 2


def test_cli_without_a_runtime_dir_says_what_to_do(monkeypatch):
    monkeypatch.delenv("XDG_RUNTIME_DIR")
    with pytest.raises(SystemExit) as info:
        asyncio.run(async_main(["status"]))
    assert "XDG_RUNTIME_DIR" in str(info.value.code)
