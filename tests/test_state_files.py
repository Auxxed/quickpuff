"""Every file QuickPuff keeps is read through one validated descriptor and
written through a private temporary renamed into place. What a reviewer (or
another process running as this user) would try: a symlink, a FIFO, another
account's file or an oversized one planted where QuickPuff looks. Each is
refused, nothing waits on it, and nothing is written over it.
"""

import json
import logging
import os
import stat
import threading

import pytest

from quickpuff import faults, history, paths, saved_lights


def finishes_quickly(fn, seconds=5.0):
    """Run fn in a thread; fail (rather than hang the suite) if it blocks."""
    box = {}

    def run():
        try:
            box["value"] = fn()
        except BaseException as exc:  # noqa: BLE001 - handed back to the test
            box["error"] = exc

    worker = threading.Thread(target=run, daemon=True)
    worker.start()
    worker.join(seconds)
    assert not worker.is_alive(), "blocked: the read waited on something it should have refused"
    if "error" in box:
        raise box["error"]
    return box.get("value")


@pytest.fixture
def victim(tmp_path):
    """A file outside QuickPuff's folders that a planted symlink points at."""
    path = tmp_path / "victim.txt"
    path.write_text("must survive\n")
    return path


@pytest.fixture
def someone_else(monkeypatch):
    """Make every file this test created look like another account's."""
    real = os.geteuid()

    def plant():
        monkeypatch.setattr(os, "geteuid", lambda: real + 1)

    return plant


# ---- read_bytes_bounded ------------------------------------------------------


class TestBoundedRead:
    def test_absent_file_is_none(self, tmp_path):
        assert paths.read_bytes_bounded(tmp_path / "nope.json", 100) is None

    def test_absent_directory_is_none(self, tmp_path):
        assert paths.read_bytes_bounded(tmp_path / "no" / "such" / "dir.json", 100) is None

    def test_reads_a_plain_file(self, tmp_path):
        target = tmp_path / "ok.json"
        target.write_bytes(b'{"a": 1}')
        assert paths.read_bytes_bounded(target, 100) == b'{"a": 1}'

    def test_exactly_at_the_limit_is_fine_and_one_past_is_refused(self, tmp_path):
        target = tmp_path / "edge.bin"
        target.write_bytes(b"x" * 64)
        assert paths.read_bytes_bounded(target, 64) == b"x" * 64
        with pytest.raises(paths.RefusedFile, match="over the 63"):
            paths.read_bytes_bounded(target, 63)

    def test_symlink_is_refused_not_followed(self, tmp_path, victim):
        link = tmp_path / "config.json"
        link.symlink_to(victim)
        with pytest.raises(paths.RefusedFile, match="symlink"):
            paths.read_bytes_bounded(link, 1000)

    def test_dangling_symlink_is_refused_not_treated_as_absent(self, tmp_path):
        link = tmp_path / "config.json"
        link.symlink_to(tmp_path / "missing")
        with pytest.raises(paths.RefusedFile):
            paths.read_bytes_bounded(link, 1000)

    def test_fifo_is_refused_without_blocking(self, tmp_path):
        fifo = tmp_path / "config.json"
        os.mkfifo(fifo)
        with pytest.raises(paths.RefusedFile, match="not a regular file"):
            finishes_quickly(lambda: paths.read_bytes_bounded(fifo, 1000))

    def test_directory_is_refused(self, tmp_path):
        (tmp_path / "config.json").mkdir()
        with pytest.raises(paths.RefusedFile, match="not a regular file"):
            paths.read_bytes_bounded(tmp_path / "config.json", 1000)

    def test_socket_is_refused(self, tmp_path):
        import socket

        path = tmp_path / "s.json"
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            server.bind(str(path))
            with pytest.raises(paths.RefusedFile):
                finishes_quickly(lambda: paths.read_bytes_bounded(path, 1000))
        finally:
            server.close()

    def test_another_accounts_file_is_refused(self, tmp_path, someone_else):
        target = tmp_path / "config.json"
        target.write_text("{}")
        someone_else()
        with pytest.raises(paths.RefusedFile, match="another user"):
            paths.read_bytes_bounded(target, 1000)

    def test_oversized_file_is_refused_before_it_is_read(self, tmp_path):
        target = tmp_path / "big.json"
        target.write_bytes(b"[" + b"0," * 10_000 + b"0]")
        with pytest.raises(paths.RefusedFile, match="over the 1000"):
            paths.read_bytes_bounded(target, 1000)


class TestBoundedJson:
    def test_bad_json_is_a_value_error_not_a_refusal(self, tmp_path):
        target = tmp_path / "x.json"
        target.write_text("{not json")
        with pytest.raises(ValueError, match="isn't valid JSON") as info:
            paths.read_json_bounded(target, 1000)
        assert not isinstance(info.value, OSError)

    def test_nesting_too_deep_to_parse_is_bad_json(self, tmp_path):
        target = tmp_path / "deep.json"
        target.write_text("[" * 100_000 + "]" * 100_000)
        with pytest.raises(ValueError, match="isn't valid JSON"):
            paths.read_json_bounded(target, 1_000_000)

    def test_bad_utf8_is_bad_json(self, tmp_path):
        target = tmp_path / "x.json"
        target.write_bytes(b'{"a": "\xff"}')
        with pytest.raises(ValueError):
            paths.read_json_bounded(target, 1000)


# ---- write_json_atomic -------------------------------------------------------


class TestAtomicWrite:
    def test_file_is_0600_from_the_start_whatever_the_umask(self, tmp_path):
        old = os.umask(0)
        try:
            paths.write_json_atomic(tmp_path / "out" / "x.json", {"a": 1})
        finally:
            os.umask(old)
        assert stat.S_IMODE((tmp_path / "out" / "x.json").stat().st_mode) == 0o600

    def test_new_directory_is_private(self, tmp_path):
        paths.write_json_atomic(tmp_path / "fresh" / "x.json", {})
        assert stat.S_IMODE((tmp_path / "fresh").stat().st_mode) == 0o700

    def test_an_existing_wide_directory_is_tightened(self, tmp_path):
        folder = tmp_path / "wide"
        folder.mkdir()
        folder.chmod(0o755)
        paths.write_json_atomic(folder / "x.json", {})
        assert stat.S_IMODE(folder.stat().st_mode) == 0o700

    def test_planted_symlink_is_left_and_its_target_untouched(self, tmp_path, victim):
        folder = tmp_path / "state"
        folder.mkdir()
        link = folder / "config.json"
        link.symlink_to(victim)
        with pytest.raises(paths.RefusedFile, match="symlink"):
            paths.write_json_atomic(link, {"evil": True})
        assert victim.read_text() == "must survive\n"
        assert link.is_symlink()
        assert sorted(p.name for p in folder.iterdir()) == ["config.json"]

    def test_planted_fifo_is_refused_without_blocking(self, tmp_path):
        fifo = tmp_path / "config.json"
        os.mkfifo(fifo)
        with pytest.raises(paths.RefusedFile):
            finishes_quickly(lambda: paths.write_json_atomic(fifo, {}))
        assert stat.S_ISFIFO(os.lstat(fifo).st_mode)

    def test_another_accounts_file_is_not_replaced(self, tmp_path, someone_else):
        target = tmp_path / "config.json"
        target.write_text('{"theirs": true}')
        someone_else()
        with pytest.raises(paths.RefusedFile, match="another user"):
            paths.write_json_atomic(target, {"mine": True})
        assert json.loads(target.read_text()) == {"theirs": True}

    def test_an_oversized_file_its_reader_refused_is_not_replaced(self, tmp_path):
        target = tmp_path / "history.json"
        target.write_bytes(b" " * 2000)
        with pytest.raises(paths.RefusedFile):
            paths.write_json_atomic(target, {}, max_bytes=1000)
        assert target.stat().st_size == 2000

    def test_nothing_bigger_than_the_reader_takes_is_written(self, tmp_path):
        folder = tmp_path / "state"
        target = folder / "x.json"
        paths.write_json_atomic(target, {"ok": 1}, max_bytes=1000)
        with pytest.raises(paths.RefusedFile):
            paths.write_json_atomic(target, {"big": "x" * 2000}, max_bytes=1000)
        assert json.loads(target.read_text()) == {"ok": 1}
        assert [p.name for p in folder.iterdir()] == ["x.json"]

    def test_a_damaged_file_of_our_own_is_replaced(self, tmp_path):
        target = tmp_path / "x.json"
        target.write_text("{not json")
        paths.write_json_atomic(target, {"fixed": True}, max_bytes=1000)
        assert json.loads(target.read_text()) == {"fixed": True}

    def test_file_and_directory_are_fsynced(self, tmp_path, monkeypatch):
        synced = []
        real = os.fsync

        def spy(fd):
            synced.append(stat.S_ISDIR(os.fstat(fd).st_mode))
            real(fd)

        monkeypatch.setattr(os, "fsync", spy)
        paths.write_json_atomic(tmp_path / "x.json", {})
        assert synced == [False, True]  # the file, then its directory after the rename

    def test_temporaries_are_unpredictable_and_exclusive(self, tmp_path, monkeypatch):
        created = []
        real_open = os.open

        def spy(name, flags, *args, **kwargs):
            if str(name).endswith(".tmp"):
                created.append((str(name), flags))
            return real_open(name, flags, *args, **kwargs)

        monkeypatch.setattr(os, "open", spy)
        paths.write_json_atomic(tmp_path / "x.json", {})
        paths.write_json_atomic(tmp_path / "x.json", {})
        assert len(created) == 2 and created[0][0] != created[1][0]
        for _name, flags in created:
            assert flags & os.O_EXCL and flags & os.O_CREAT and flags & os.O_NOFOLLOW


# ---- runtime directory -------------------------------------------------------


class TestRuntimeDir:
    def test_unset_fails_closed(self, monkeypatch):
        monkeypatch.delenv("XDG_RUNTIME_DIR")
        with pytest.raises(paths.RuntimeDirMissing, match="won't fall back to /tmp"):
            paths.runtime_dir()
        with pytest.raises(paths.RuntimeDirMissing):
            paths.socket_path()
        with pytest.raises(paths.RuntimeDirMissing):
            paths.log_path()

    def test_relative_is_treated_as_unset(self, monkeypatch):
        monkeypatch.setenv("XDG_RUNTIME_DIR", "run/user")
        with pytest.raises(paths.RuntimeDirMissing):
            paths.runtime_dir()

    def test_no_tmp_fallback_anywhere(self):
        source = (paths.__file__ and open(paths.__file__).read())
        assert "/tmp/quickpuff" not in source

    def test_explicit_socket_override_still_works(self, monkeypatch, tmp_path):
        monkeypatch.delenv("XDG_RUNTIME_DIR")
        monkeypatch.setenv("QUICKPUFF_SOCKET", str(tmp_path / "q.sock"))
        assert paths.socket_path() == tmp_path / "q.sock"


# ---- config.json -------------------------------------------------------------


class TestConfigRefusals:
    def test_symlinked_config_reads_as_defaults_and_is_never_saved_over(self, victim, caplog):
        path = paths.config_path()
        path.parent.mkdir(parents=True)
        path.symlink_to(victim)
        with caplog.at_level(logging.WARNING, logger="quickpuff.paths"):
            assert paths.load_config() == paths.DEFAULTS
            paths.load_config()
        warnings = [r for r in caplog.records if r.levelno == logging.WARNING]
        assert len(warnings) == 1  # said once, not on every poll
        assert "is a symlink" in warnings[0].getMessage()
        with pytest.raises(paths.RefusedFile):
            paths.save_config({"units": "C"})
        assert victim.read_text() == "must survive\n"
        assert path.is_symlink()

    def test_fifo_config_does_not_hang_and_is_left(self):
        path = paths.config_path()
        path.parent.mkdir(parents=True)
        os.mkfifo(path)
        assert finishes_quickly(paths.load_config) == paths.DEFAULTS
        with pytest.raises(paths.RefusedFile):
            finishes_quickly(lambda: paths.save_config({"units": "C"}))
        assert stat.S_ISFIFO(os.lstat(path).st_mode)

    def test_oversized_config_is_refused_and_kept(self):
        path = paths.config_path()
        path.parent.mkdir(parents=True)
        blob = json.dumps({"units": "C", "pad": "x" * (paths.MAX_CONFIG_BYTES + 10)})
        path.write_text(blob)
        assert paths.load_config()["units"] == "F"
        with pytest.raises(paths.RefusedFile):
            paths.save_config({"units": "C"})
        assert path.read_text() == blob

    def test_another_accounts_config_is_refused_and_kept(self, someone_else):
        path = paths.config_path()
        path.parent.mkdir(parents=True)
        path.write_text('{"units": "C"}')
        someone_else()
        assert paths.load_config()["units"] == "F"
        with pytest.raises(paths.RefusedFile):
            paths.save_config({"units": "F"})
        assert path.read_text() == '{"units": "C"}'

    def test_a_damaged_config_still_reads_as_defaults_and_is_replaced(self):
        path = paths.config_path()
        path.parent.mkdir(parents=True)
        path.write_text("{ this is not json")
        assert paths.load_config() == paths.DEFAULTS
        paths.save_config({"units": "C"})
        assert paths.load_config()["units"] == "C"

    def test_saved_config_is_private(self):
        paths.save_config({"units": "C"})
        assert stat.S_IMODE(paths.config_path().stat().st_mode) == 0o600
        assert stat.S_IMODE(paths.config_dir().stat().st_mode) == 0o700


# ---- the ui block --------------------------------------------------------------


class TestUiSettings:
    KEYS = {"ready_animation", "showtime", "sounds", "sound_volume", "overlay_screen", "units"}

    def test_defaults(self):
        assert paths.ui_settings() == {
            "ready_animation": "rocket",
            "showtime": "corner",
            "sounds": True,
            "sound_volume": 70,
            "overlay_screen": "focused",
            "units": "F",
        }

    def test_saved_values_come_through(self):
        paths.save_config(
            {
                "ready_animation": "lava",
                "showtime": "stage",
                "sounds": False,
                "sound_volume": 35,
                "overlay_screen": "DP-2",
                "units": "C",
            }
        )
        assert paths.ui_settings() == {
            "ready_animation": "lava",
            "showtime": "stage",
            "sounds": False,
            "sound_volume": 35,
            "overlay_screen": "DP-2",
            "units": "C",
        }

    @pytest.mark.parametrize(
        "key,value,shown",
        [
            ("ready_animation", "<img src=x>", "rocket"),
            ("ready_animation", ["lava"], "rocket"),
            ("showtime", "fullscreen", "corner"),
            ("showtime", None, "corner"),
            ("sounds", "off", False),
            ("sounds", "yes", True),
            ("sound_volume", 150, 100),
            ("sound_volume", -3, 0),
            ("sound_volume", "40", 40),
            ("sound_volume", float("nan"), 70),
            ("sound_volume", float("inf"), 70),
            ("sound_volume", True, 70),
            ("sound_volume", "loud", 70),
            ("overlay_screen", "DP 2; reboot", "focused"),
            ("overlay_screen", "A" * 33, "focused"),
            ("overlay_screen", "A" * 32, "A" * 32),
            ("overlay_screen", "-DP-2", "focused"),
            ("overlay_screen", "Focused", "focused"),
            ("overlay_screen", 7, "focused"),
            ("units", "c", "C"),
            ("units", "kelvin", "F"),
            ("units", None, "F"),
        ],
    )
    def test_every_value_is_checked(self, key, value, shown):
        ui = paths.ui_settings({**paths.DEFAULTS, key: value})
        assert set(ui) == self.KEYS
        assert ui[key] == shown
        assert type(ui[key]) is type(shown)

    def test_hand_edited_infinity_in_config_reads_as_default(self):
        path = paths.config_path()
        path.parent.mkdir(parents=True)
        path.write_text('{"sound_volume": Infinity, "units": "C"}')
        assert paths.ui_settings()["sound_volume"] == 70
        assert paths.ui_settings()["units"] == "C"

    def test_a_refused_config_gives_the_defaults(self, victim):
        path = paths.config_path()
        path.parent.mkdir(parents=True)
        path.symlink_to(victim)
        assert paths.ui_settings()["units"] == "F"


def test_device_file_stem_is_safe_and_bounded():
    assert paths.device_file_stem("../79AAN/BTBA 264") == "_79AAN_BTBA_264"
    assert paths.device_file_stem("..") == "peak"
    assert paths.device_file_stem("") == "peak"
    assert len(paths.device_file_stem("A" * 5000)) == 64
    assert paths.device_file_stem("79AAN-BTBA264-04886") == "79AAN-BTBA264-04886"


# ---- the modules that keep state ----------------------------------------------


class TestHistoryRefusals:
    def test_symlinked_history_reads_empty_and_is_never_written_over(self, victim):
        history.use_device("PEAK")
        path = history.history_path()
        path.parent.mkdir(parents=True)
        path.symlink_to(victim)
        assert history.get_stats()["tracked_total"] == 0
        assert history.record_total(500) is None
        event = history.record_cycle(temp_f=500)
        assert event["delta"] == 1  # the dab still happened; it just isn't written down
        assert history.record_battery(event["ts"], 50) is False
        assert victim.read_text() == "must survive\n"
        assert path.is_symlink()

    def test_a_note_on_a_refused_history_is_an_error_not_a_silent_loss(self, victim):
        history.use_device("PEAK")
        path = history.history_path()
        path.parent.mkdir(parents=True)
        path.symlink_to(victim)
        with pytest.raises(paths.RefusedFile):
            history.set_note("t123", "nice")
        assert victim.read_text() == "must survive\n"

    def test_oversized_history_is_kept_not_replaced_by_a_fresh_one(self, monkeypatch):
        monkeypatch.setattr(history, "MAX_HISTORY_BYTES", 2000)
        history.use_device("PEAK")
        path = history.history_path()
        path.parent.mkdir(parents=True)
        blob = json.dumps({"last_total": 100, "events": [{"ts": 1, "delta": 1}] * 200})
        path.write_text(blob)
        assert history.get_stats()["tracked_total"] == 0
        history.record_total(105)
        history.record_cycle(temp_f=500)
        assert path.read_text() == blob

    def test_fifo_history_does_not_hang_the_daemon(self):
        history.use_device("PEAK")
        path = history.history_path()
        path.parent.mkdir(parents=True)
        os.mkfifo(path)
        stats = finishes_quickly(history.get_stats)
        assert stats["tracked_total"] == 0
        finishes_quickly(lambda: history.record_total(5))
        assert stat.S_ISFIFO(os.lstat(path).st_mode)

    def test_a_symlinked_shared_history_is_not_adopted(self, victim):
        legacy = history.history_path()
        legacy.parent.mkdir(parents=True)
        legacy.symlink_to(victim)
        history.use_device("MINE")
        assert legacy.is_symlink()
        assert not history.history_path().exists()

    def test_history_files_are_private(self):
        history.use_device("PEAK")
        history.record_total(500)
        assert stat.S_IMODE(history.history_path().stat().st_mode) == 0o600
        assert stat.S_IMODE(history.history_path().parent.stat().st_mode) == 0o700


class TestSavedLightsRefusals:
    RAW = bytes.fromhex("a1636c6f6f6b65736f6c6964")

    def test_symlinked_lights_read_as_none_and_saving_says_so(self, victim):
        path = saved_lights._path()
        path.parent.mkdir(parents=True)
        path.symlink_to(victim)
        assert saved_lights.listing() == []
        with pytest.raises(paths.RefusedFile):
            saved_lights.save("Mine", self.RAW)
        assert victim.read_text() == "must survive\n"

    def test_more_lights_than_save_keeps_is_not_believed(self):
        path = saved_lights._path()
        path.parent.mkdir(parents=True)
        lights = [{"id": f"{i:012x}", "name": f"L{i}", "raw": "aa"} for i in range(saved_lights.MAX_SAVED + 1)]
        path.write_text(json.dumps({"lights": lights}))
        assert saved_lights.listing() == []

    def test_malformed_and_oversized_entries_are_dropped(self):
        path = saved_lights._path()
        path.parent.mkdir(parents=True)
        lights = [
            {"id": "aaaaaaaaaaaa", "name": "ok", "raw": "a1"},
            {"id": "bbbbbbbbbbbb", "name": "huge", "raw": "aa" * (saved_lights.MAX_RAW + 1)},
            {"id": "cccccccccccc", "name": "x" * 500, "raw": "a1"},
            {"id": 7, "name": "bad id", "raw": "a1"},
            "not a light",
        ]
        path.write_text(json.dumps({"lights": lights}))
        assert [x["id"] for x in saved_lights.listing()] == ["aaaaaaaaaaaa"]

    def test_a_refused_cycle_memo_does_not_fail_the_light_change(self, victim):
        path = saved_lights._memo_path()
        path.parent.mkdir(parents=True)
        path.symlink_to(victim)
        saved_lights.remember_cycle(self.RAW, {"style": "fade", "colors": ["#ff0000"]})
        assert saved_lights.recall_cycle(self.RAW) is None
        assert victim.read_text() == "must survive\n"

    def test_a_memo_entry_of_the_wrong_shape_is_ignored(self):
        path = saved_lights._memo_path()
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({saved_lights.light_id(self.RAW): {"style": 5}}))
        assert saved_lights.recall_cycle(self.RAW) is None


class TestFaultCacheRefusals:
    def test_symlinked_cache_starts_empty_and_is_left(self, victim):
        path = faults.cache_path("PEAK")
        path.parent.mkdir(parents=True)
        path.symlink_to(victim)
        cache = faults.load_cache("PEAK")
        assert cache["entries"] == {}
        cache["end"] = 5
        faults.save_cache(cache)  # only a cache: logged, not raised
        assert victim.read_text() == "must survive\n"
        assert path.is_symlink()

    def test_oversized_cache_is_left(self, monkeypatch):
        monkeypatch.setattr(faults, "MAX_CACHE_BYTES", 100)
        path = faults.cache_path("PEAK")
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({"end": 1, "pad": "x" * 200}))
        before = path.read_text()
        cache = faults.load_cache("PEAK")
        faults.save_cache(cache)
        assert path.read_text() == before
