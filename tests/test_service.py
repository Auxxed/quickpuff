"""Regression cover for the stale-socket lockout.

A daemon killed with SIGKILL leaves its socket file behind. Treating that
file as proof of life meant ensure_daemon() never respawned, and every
CLI call failed until the socket was deleted by hand.
"""

import socket

from quickpuff import service


class TestDaemonRunning:
    def test_absent_socket_is_not_running(self, monkeypatch, tmp_path):
        monkeypatch.setenv("QUICKPUFF_SOCKET", str(tmp_path / "nothing.sock"))
        assert service.daemon_running() is False

    def test_stale_socket_file_is_not_running(self, monkeypatch, tmp_path):
        stale = tmp_path / "quickpuff.sock"
        stale.write_text("")
        monkeypatch.setenv("QUICKPUFF_SOCKET", str(stale))
        assert service.daemon_running() is False

    def test_listening_socket_is_running(self, monkeypatch, tmp_path):
        live = tmp_path / "quickpuff.sock"
        monkeypatch.setenv("QUICKPUFF_SOCKET", str(live))
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            server.bind(str(live))
            server.listen(1)
            assert service.daemon_running() is True
        finally:
            server.close()

    def test_socket_stops_counting_once_the_listener_goes_away(self, monkeypatch, tmp_path):
        """Exactly the SIGKILL shape: the file outlives the process."""
        path = tmp_path / "quickpuff.sock"
        monkeypatch.setenv("QUICKPUFF_SOCKET", str(path))
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(str(path))
        server.listen(1)
        assert service.daemon_running() is True

        server.close()  # file remains on disk, nothing is listening
        assert path.exists()
        assert service.daemon_running() is False


class TestSystemdOwnsDaemon:
    def test_active_unit_is_owned(self, monkeypatch):
        monkeypatch.setattr(
            service, "run_bounded", lambda *_a, **_k: (0, "ActiveState=active\nUnitFileState=enabled")
        )
        assert service.systemd_owns_daemon() is True

    def test_restart_window_is_owned(self, monkeypatch):
        monkeypatch.setattr(
            service, "run_bounded", lambda *_a, **_k: (0, "ActiveState=deactivating\nUnitFileState=enabled")
        )
        assert service.systemd_owns_daemon() is True

    def test_disabled_and_inactive_is_not_owned(self, monkeypatch):
        monkeypatch.setattr(
            service, "run_bounded", lambda *_a, **_k: (0, "ActiveState=inactive\nUnitFileState=disabled")
        )
        assert service.systemd_owns_daemon() is False

    def test_missing_systemctl_is_not_owned(self, monkeypatch):
        # run_bounded's answer for a command that can't run, or overran.
        monkeypatch.setattr(service, "run_bounded", lambda *_a, **_k: (127, ""))
        assert service.systemd_owns_daemon() is False

    def test_systemctl_is_asked_by_its_full_path_with_a_deadline(self, monkeypatch):
        seen = {}

        def fake(argv, **kwargs):
            seen.update(argv=argv, **kwargs)
            return 0, ""

        monkeypatch.setattr(service, "run_bounded", fake)
        service.systemd_owns_daemon()
        assert seen["argv"][0] == "/usr/bin/systemctl"
        assert seen["timeout"] <= 2

    def test_ensure_waits_instead_of_spawning_when_systemd_owns(self, monkeypatch, tmp_path):
        spawned = []
        monkeypatch.setattr(service, "daemon_running", lambda: False)
        monkeypatch.setattr(
            service,
            "unit_state",
            lambda: {"LoadState": "loaded", "ActiveState": "activating", "UnitFileState": "enabled"},
        )
        monkeypatch.setattr(service, "log_path", lambda: tmp_path / "daemon.log")
        monkeypatch.setattr(service.time, "time", lambda: 0)
        monkeypatch.setattr(
            service.subprocess,
            "Popen",
            lambda *a, **k: spawned.append(True),
        )

        try:
            service.ensure_daemon(timeout=0)
        except RuntimeError as exc:
            assert "systemd daemon did not come back" in str(exc)
        else:
            raise AssertionError("expected ensure_daemon to fail closed")
        assert spawned == []
